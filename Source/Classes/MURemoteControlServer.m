// Copyright 2012-2026 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style license in LICENSE.
#import "MURemoteControlServer.h"
#import "MLClient.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <unistd.h>

@implementation MURemoteControlServer {
    dispatch_queue_t _queue;
    dispatch_source_t _listener;
    dispatch_group_t _pendingCloses;
    NSMutableDictionary<NSNumber *, id> *_clients;
}
+ (instancetype)sharedRemoteControlServer {
    static MURemoteControlServer *server;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ server = [self new]; });
    return server;
}
- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("info.mumble.remote-control", DISPATCH_QUEUE_SERIAL);
        _clients = [NSMutableDictionary dictionary];
        _pendingCloses = dispatch_group_create();
    }
    return self;
}
- (void)addClient:(int)fd {
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
    int one = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
    dispatch_source_t reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, _queue);
    if (!reader) { close(fd); return; }
    NSNumber *key = @(fd);
    _clients[key] = reader;
    __weak MURemoteControlServer *weakSelf = self;
    dispatch_group_t closes = _pendingCloses;
    dispatch_group_enter(closes);
    dispatch_source_set_cancel_handler(reader, ^{ close(fd); dispatch_group_leave(closes); });
    dispatch_source_set_event_handler(reader, ^{
        MURemoteControlServer *server = weakSelf;
        if (!server || !server->_clients[key]) return;
        unsigned char actions[256]; ssize_t count;
        NSUInteger batches = 0;
        while (batches++ < 32 && (count = recv(fd, actions, sizeof(actions), 0)) > 0) {
            for (ssize_t i = 0; i < count; ++i)
                if ((actions[i] & ~1) == 0) [MLAudio sharedAudio].forceTransmit = (actions[i] & 1) != 0;
        }
        if (count == 0 || (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)) {
            dispatch_source_cancel((dispatch_source_t)server->_clients[key]);
            [server->_clients removeObjectForKey:key];
            [MLAudio sharedAudio].forceTransmit = NO;
        }
    });
    dispatch_resume(reader);
}
- (BOOL)start {
    if (_listener) return YES;
    int fd = socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP);
    if (fd < 0) return NO;
    int one = 1; setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
    struct sockaddr_in6 address = {0};
    address.sin6_len = sizeof(address); address.sin6_family = AF_INET6;
    address.sin6_port = htons(54295); address.sin6_addr = in6addr_any;
    if (bind(fd, (const struct sockaddr *)&address, sizeof(address)) || listen(fd, 16)) { close(fd); return NO; }
    _listener = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, _queue);
    if (!_listener) { close(fd); return NO; }
    __weak MURemoteControlServer *weakSelf = self;
    dispatch_group_t closes = _pendingCloses;
    dispatch_group_enter(closes);
    dispatch_source_set_cancel_handler(_listener, ^{ close(fd); dispatch_group_leave(closes); });
    dispatch_source_set_event_handler(_listener, ^{
        MURemoteControlServer *server = weakSelf;
        if (!server) return;
        int client;
        while ((client = accept(fd, NULL, NULL)) >= 0) [server addClient:client];
    });
    dispatch_resume(_listener);
    return YES;
}
- (BOOL)stop {
    dispatch_sync(_queue, ^{
        for (dispatch_source_t reader in self->_clients.allValues) dispatch_source_cancel(reader);
        [self->_clients removeAllObjects];
        if (self->_listener) dispatch_source_cancel(self->_listener);
        self->_listener = nil;
        [MLAudio sharedAudio].forceTransmit = NO;
    });
    // Complete pending cancellation handlers before a quick stop/start rebinds the port.
    dispatch_group_wait(_pendingCloses, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
    return YES;
}
- (BOOL)isRunning { return _listener != nil; }
- (void)dealloc {
    if (_listener) dispatch_source_cancel(_listener);
    for (dispatch_source_t reader in _clients.allValues) dispatch_source_cancel(reader);
}
@end
