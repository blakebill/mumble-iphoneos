// Copyright 2009-2012 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MUMessagesDatabase.h"
#import "MUTextMessage.h"
#import "MUDataURL.h"

#import "MLClient.h"

#import <FMDB/FMDatabase.h>

@interface MUMessagesDatabase () {
    NSCache    *_msgCache;
    FMDatabase *_db;
    NSInteger  _count;
}
@end

@implementation MUMessagesDatabase

- (id) init {
    if ((self = [super init])) {
        NSString *directory = NSTemporaryDirectory();
        NSString *dbPath = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"msg-%@.db", [[NSUUID UUID] UUIDString]]];
        _db = [[FMDatabase alloc] initWithPath:dbPath];
        if (![_db open]) {
            NSLog(@"MUMessagesDatabse: Failed to open.");
        }
        
        [_db executeUpdate:@"CREATE TABLE IF NOT EXISTS `msg` "
                           @"(`id` INTEGER PRIMARY KEY AUTOINCREMENT,"
                           @" `plist` BLOB)"];
        
        _msgCache = [[NSCache alloc] init];
        // This store is deliberately temporary; avoid durable disk synchronization per message.
        [_db executeUpdate:@"PRAGMA journal_mode=MEMORY"];
        [_db executeUpdate:@"PRAGMA synchronous=OFF"];
        [_msgCache setCountLimit:128];
        [_msgCache setTotalCostLimit:24 * 1024 * 1024];
    }
    return self;
}

- (void)dealloc {
    NSString *path = _db.databasePath;
    [_db close];
    if (path) [NSFileManager.defaultManager removeItemAtPath:path error:nil];
}

- (void) addMessage:(MLTextMessage *)msg withHeading:(NSString *)heading andSentBySelf:(BOOL)selfSent {
    NSError *err = nil;
    NSString *plainMsg = [msg plainTextString];
    plainMsg = [plainMsg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *imageDataArray = [[NSMutableArray alloc] initWithCapacity:[[msg embeddedImages] count]];
    for (NSString *dataUrl in [msg embeddedImages]) {
        NSData *imgData = [MUDataURL dataFromDataURL:dataUrl];
        if (imgData) {
            [imageDataArray addObject:imgData];
        }
    }
    
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                heading, @"heading",
                                plainMsg, @"msg",
                                [NSDate date], @"date",
                                [msg embeddedLinks], @"links",
                                imageDataArray, @"images",
                                [NSNumber numberWithBool:selfSent], @"selfsent",
                          nil];
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:dict format:NSPropertyListBinaryFormat_v1_0 options:0 error:&err];
    [_db executeUpdate:@"INSERT INTO `msg` (`plist`) VALUES (?)", plist ? plist : [NSNull null]];
    _count++;
}

- (void) clearMessageAtIndex:(NSInteger)row {
    [_db executeUpdate:@"UPDATE `msg` SET `plist`=NULL WHERE `id`=?", [NSNumber numberWithInteger:row+1]];
    [_msgCache removeObjectForKey:[NSNumber numberWithInteger:row+1]];
}

- (MUTextMessage *) messageAtIndex:(NSInteger)row {
    MUTextMessage *txtMsg = [_msgCache objectForKey:[NSNumber numberWithInteger:row+1]];
    if (txtMsg != nil)
        return txtMsg;
    
    FMResultSet *result = [_db executeQuery:@"SELECT `plist` FROM `msg` WHERE `id` = ?", [NSNumber numberWithInteger:row+1]];
    if ([result next]) {
        NSData *plistData = [result dataForColumnIndex:0];
        if (plistData) {
            NSDictionary *dict = [NSPropertyListSerialization propertyListWithData:plistData options:0 format:nil error:nil];
            if (dict) {
                NSArray *imgDataArray = [dict objectForKey:@"images"];
                NSMutableArray *imagesArray = [[NSMutableArray alloc] initWithCapacity:[imgDataArray count]];
                for (NSData *data in imgDataArray) {
                    UIImage *image = [UIImage imageWithData:data];
                    if (image) [imagesArray addObject:image];
                }
                txtMsg = [MUTextMessage textMessageWithHeading:[dict objectForKey:@"heading"]
                                                    andMessage:[dict objectForKey:@"msg"]
                                              andEmbeddedLinks:[dict objectForKey:@"links"]
                                             andEmbeddedImages:imagesArray
                                              andTimestampDate:[dict objectForKey:@"date"]
                                                  isSentBySelf:[[dict objectForKey:@"selfsent"] boolValue]];
                NSUInteger cost = [[dict objectForKey:@"msg"] length] * 2;
                for (UIImage *image in imagesArray) cost += (NSUInteger)(image.size.width * image.scale * image.size.height * image.scale * 4);
                [_msgCache setObject:txtMsg forKey:@(row+1) cost:cost];
                [result close];
                return txtMsg;
            }
        }
    }
    [result close];
    return nil;
}

- (NSInteger) count {
    return _count;
}

@end
