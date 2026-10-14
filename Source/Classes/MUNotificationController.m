// Use of this source code is governed by the BSD-style license in LICENSE.
#import "MUNotificationController.h"

@implementation MUNotificationController {
    NSMutableArray<NSString *> *_notificationQueue;
    BOOL _running;
}
+ (MUNotificationController *)sharedController {
    static MUNotificationController *controller; static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [self new]; }); return controller;
}
- (id)init {
    if ((self = [super init])) {
        _notificationQueue = [NSMutableArray array];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(becameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)becameActive:(NSNotification *)notification { if (!_running) [self showNext]; }
- (void)addNotification:(NSString *)text {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self addNotification:text]; }); return; }
    if (text.length && _notificationQueue.count < 10) [_notificationQueue addObject:[text copy]];
    if (!_running) [self showNext];
}
- (void)showNext {
    if (!_notificationQueue.count || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) { _running = NO; return; }
    _running = YES;
    UIViewController *presenter = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) presenter = window.rootViewController;
    }
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    if (!presenter || [presenter isKindOfClass:UIAlertController.class] || presenter.isBeingPresented || presenter.isBeingDismissed || presenter.transitionCoordinator) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{ [self showNext]; });
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Server Notice", nil) message:_notificationQueue.firstObject preferredStyle:UIAlertControllerStyleAlert];
    [_notificationQueue removeObjectAtIndex:0];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        self->_running = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ [self showNext]; });
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
@end
