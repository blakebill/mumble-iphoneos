// Copyright 2009-2011 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MUDatabase.h"
#import "MUFavouriteServer.h"

static FMDatabase *db = nil;
static void *MUDatabaseQueueKey = &MUDatabaseQueueKey;

static dispatch_queue_t MUDatabaseQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("info.mumble.database", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(queue, MUDatabaseQueueKey, MUDatabaseQueueKey, NULL);
    });
    return queue;
}

static void MUDatabasePerform(dispatch_block_t block) {
    if (dispatch_get_specific(MUDatabaseQueueKey) == MUDatabaseQueueKey) {
        block();
    } else {
        dispatch_sync(MUDatabaseQueue(), block);
    }
}

@interface MUDatabase ()
+ (NSString *) filePath;
+ (void) moveOldDatabases;
+ (void) openDatabaseIfNeeded;
+ (void) storeFavouriteOnQueue:(MUFavouriteServer *)favServ;
@end

@implementation MUDatabase

+ (NSString *) filePath {
    NSArray *libraryDirectories = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
                                                                      NSUserDomainMask,
                                                                      YES);
    NSString *library = [libraryDirectories objectAtIndex:0];
    [[NSFileManager defaultManager] createDirectoryAtPath:library withIntermediateDirectories:YES attributes:nil error:nil];
    return [library stringByAppendingPathComponent:@"mumble.sqlite"];
}

+ (void) moveOldDatabases {
    NSArray *documentDirectories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                       NSUserDomainMask,
                                                                       YES);
    NSString *docs = [documentDirectories objectAtIndex:0];
    
    NSError *err = nil;
    NSFileManager *manager = [NSFileManager defaultManager];
    
    // Hide the SQLite database from the iTunes document inspector.
    NSString *oldPath = [docs stringByAppendingPathComponent:@"mumble.sqlite"];
    NSString *newPath = [docs stringByAppendingPathComponent:@".mumble.sqlite"];
    if (![manager fileExistsAtPath:newPath] && [manager fileExistsAtPath:oldPath]) {
        if (![manager moveItemAtPath:oldPath toPath:newPath error:&err]) {
            NSLog(@"MUDatabase: unable to move file to new spot (mumble.sqlite -> .mumble.sqlite)");
        }
    }

    // Attempt to move an old database to the new location.
    NSString *correctPath = [MUDatabase filePath];
    if (![manager fileExistsAtPath:correctPath]) {
        oldPath = newPath;
        newPath = correctPath;
        if (![manager fileExistsAtPath:newPath] && [manager fileExistsAtPath:oldPath]) {
            if (![manager moveItemAtPath:oldPath toPath:newPath error:&err]) {
                NSLog(@"MUDatabase: Unable to move file to new spot (~/Documents -> ~/Library)");
            }
        }
    }
}

// Initialize the database.
+ (void) initializeDatabase {
    dispatch_async(MUDatabaseQueue(), ^{
        [self openDatabaseIfNeeded];
    });
}

+ (void) openDatabaseIfNeeded {
    if (db != nil) {
        return;
    }
    NSLog(@"Initializing database with SQLite version: %@", [FMDatabase sqliteLibVersion]);

    // Attempt to move old databases if we find ones
    // in our old locations.
    [MUDatabase moveOldDatabases];
    
    NSString *dbPath = [MUDatabase filePath];
    db = [[FMDatabase alloc] initWithPath:dbPath];
    if (!db)
        return;

    if ([db open]) {
        NSLog(@"MUDatabase: Initialized database at %@", dbPath);
    } else {
        NSLog(@"MUDatabase: Could not open database at %@", dbPath);
        db = nil;
        return;
    }

    [db executeUpdate:@"CREATE TABLE IF NOT EXISTS `favourites` "
                      @"(`id` INTEGER PRIMARY KEY AUTOINCREMENT,"
                      @" `name` TEXT,"
                      @" `hostname` TEXT,"
                      @" `port` INTEGER DEFAULT 64738,"
                      @" `username` TEXT,"
                      @" `password` TEXT)"];

    [db executeUpdate:@"CREATE TABLE IF NOT EXISTS `cert` "
                      @"(`id` INTEGER PRIMARY KEY AUTOINCREMENT,"
                      @" `hostname` TEXT,"
                      @" `port` INTEGER,"
                      @" `digest` TEXT)"];
    [db executeUpdate:@"CREATE UNIQUE INDEX IF NOT EXISTS `cert_host_port`"
                      @" on `cert`(`hostname`,`port`)"];
    [db executeUpdate:@"CREATE TABLE IF NOT EXISTS `recent_servers` "
                      @"(`id` INTEGER PRIMARY KEY AUTOINCREMENT,"
                      @" `hostname` TEXT NOT NULL COLLATE NOCASE,"
                      @" `port` INTEGER NOT NULL,"
                      @" `name` TEXT,"
                      @" `username` TEXT,"
                      @" UNIQUE(`hostname`,`port`))"];
    [db executeUpdate:@"CREATE TABLE IF NOT EXISTS `usernames` "
                      @"(`id` INTEGER PRIMARY KEY AUTOINCREMENT,"
                      @" `hostname` TEXT,"
                      @" `port` INTEGER,"
                      @" `username` TEXT)"];
    [db executeUpdate:@"CREATE UNIQUE INDEX IF NOT EXISTS `usernames_host_port`"
                      @" on `usernames`(`hostname`,`port`)"];
    [db executeUpdate:@"CREATE TABLE IF NOT EXISTS `tokens` "
                      @"(`id` INTEGER PRIMARY KEY AUTOINCREMENT,"
                      @" `hostname` TEXT,"
                      @" `port` INTEGER,"
                      @" `tokens` BLOB)"];
    [db executeUpdate:@"CREATE UNIQUE INDEX IF NOT EXISTS `tokens_host_port`"
                      @" on `tokens`(`hostname`,`port`)"];

    if ([db hadError]) {
        NSLog(@"MUDatabase: Error: %@ (Code: %i)", [db lastErrorMessage], [db lastErrorCode]);
    }
}

// Store a single favourite
+ (void) storeFavourite:(MUFavouriteServer *)favServ {
    MUDatabasePerform(^{
        [self openDatabaseIfNeeded];
        [self storeFavouriteOnQueue:favServ];
    });
}

+ (void)storePassword:(NSString *)password forFavouriteWithPrimaryKey:(NSInteger)primaryKey {
    if (primaryKey < 0 || !password.length) return;
    MUDatabasePerform(^{
        [self openDatabaseIfNeeded];
        [db executeUpdate:@"UPDATE `favourites` SET `password`=? WHERE `id`=?", password, @(primaryKey)];
    });
}

+ (void) storeFavouriteOnQueue:(MUFavouriteServer *)favServ {
    // If the favourite already has a primary key, update the currently stored entity
    if ([favServ hasPrimaryKey]) {
        [db executeUpdate:@"UPDATE `favourites` SET `name`=?, `hostname`=?, `port`=?, `username`=?, `password`=? WHERE `id`=?",
            [favServ displayName],
            [favServ hostName],
            [NSString stringWithFormat:@"%lu", (unsigned long)[favServ port]],
            [favServ userName],
            [favServ password],
            [NSNumber numberWithInteger:[favServ primaryKey]]];
    // If it isn't already stored, store it and update the object's pkey.
    } else {
        // We're already inside a transaction if we were called from within
        // storeFavourites. If that isn't the case, make sure we start a new
        // transaction.
        BOOL newTransaction = ![db isInTransaction];
        if (newTransaction)
            [db beginTransaction];
        [db executeUpdate:@"INSERT INTO `favourites` (`name`, `hostname`, `port`, `username`, `password`) VALUES (?, ?, ?, ?, ?)",
            [favServ displayName],
            [favServ hostName],
            [NSString stringWithFormat:@"%lu", (unsigned long)[favServ port]],
            [favServ userName],
            [favServ password]];
        FMResultSet *res = [db executeQuery:@"SELECT last_insert_rowid()"];
        [res next];
        [favServ setPrimaryKey:[res intForColumnIndex:0]];
        if (newTransaction)
            [db commit];
    }
}

// Delete a particular favourite
+ (void) deleteFavourite:(MUFavouriteServer *)favServ {
    MUDatabasePerform(^{
        [self openDatabaseIfNeeded];
        NSAssert([favServ hasPrimaryKey], @"Cannot delete a FavouriteServer not originated from the database.");
        [db executeUpdate:@"DELETE FROM `favourites` WHERE `id`=?", [NSNumber numberWithInteger:[favServ primaryKey]]];
    });
}

// Save favourites
+ (void) storeFavourites:(NSArray *)favourites {
    MUDatabasePerform(^{
        [self openDatabaseIfNeeded];
        [db beginTransaction];
        for (MUFavouriteServer *favServ in favourites) {
            [self storeFavouriteOnQueue:favServ];
        }
        [db commit];
    });
}

// Fetch all favourites
+ (NSMutableArray *) fetchAllFavourites {
    __block NSMutableArray *favs = nil;
    MUDatabasePerform(^{
        [self openDatabaseIfNeeded];
        favs = [[NSMutableArray alloc] init];
        FMResultSet *res = [db executeQuery:@"SELECT `id`, `name`, `hostname`, `port`, `username`, `password` FROM `favourites`"];
        while ([res next]) {
            MUFavouriteServer *fs = [[MUFavouriteServer alloc] init];
            [fs setPrimaryKey:[res intForColumnIndex:0]];
            [fs setDisplayName:[res stringForColumnIndex:1]];
            [fs setHostName:[res stringForColumnIndex:2]];
            [fs setPort:[res intForColumnIndex:3]];
            [fs setUserName:[res stringForColumnIndex:4]];
            [fs setPassword:[res stringForColumnIndex:5]];
            [favs addObject:fs];
        }
        [res close];
    });
    return favs;
}

#pragma mark -
#pragma mark Recent connections

+ (void)recordRecentServerWithHostname:(NSString *)hostname port:(NSUInteger)port displayName:(NSString *)displayName username:(NSString *)username {
    NSString *host = [[hostname stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if (!host.length || port == 0 || port > UINT16_MAX) return;
    MUDatabasePerform(^{
        [self openDatabaseIfNeeded];
        [db beginTransaction];
        [db executeUpdate:@"INSERT OR REPLACE INTO `recent_servers` (`hostname`,`port`,`name`,`username`) VALUES (?,?,?,?)",
            host, @(port), displayName.length ? displayName : hostname, username ?: @""];
        [db executeUpdate:@"DELETE FROM `recent_servers` WHERE `id` NOT IN (SELECT `id` FROM `recent_servers` ORDER BY `id` DESC LIMIT 3)"];
        [db commit];
    });
}

+ (NSArray<MUFavouriteServer *> *)recentServers {
    __block NSMutableArray *servers = [NSMutableArray array];
    MUDatabasePerform(^{
        [self openDatabaseIfNeeded];
        FMResultSet *rows = [db executeQuery:@"SELECT `hostname`,`port`,`name`,`username` FROM `recent_servers` ORDER BY `id` DESC LIMIT 3"];
        while ([rows next]) {
            [servers addObject:[[MUFavouriteServer alloc] initWithDisplayName:[rows stringForColumn:@"name"] hostName:[rows stringForColumn:@"hostname"] port:[rows intForColumn:@"port"] userName:[rows stringForColumn:@"username"] password:nil]];
        }
        [rows close];
    });
    return servers;
}

+ (void)deleteRecentServer:(MUFavouriteServer *)server {
    MUDatabasePerform(^{
        [self openDatabaseIfNeeded];
        [db executeUpdate:@"DELETE FROM `recent_servers` WHERE `hostname`=? AND `port`=?", server.hostName.lowercaseString, @(server.port)];
    });
}

#pragma mark Certificate verification

+ (void) storeDigest:(NSString *)hash forServerWithHostname:(NSString *)hostname port:(NSInteger)port {
    MUDatabasePerform(^{
        [self openDatabaseIfNeeded];
        [db executeUpdate:@"REPLACE INTO `cert` (`hostname`,`port`,`digest`) VALUES (?,?,?)",
               hostname, [NSNumber numberWithInteger:port], hash];
    });
}

+ (NSString *) digestForServerWithHostname:(NSString *)hostname port:(NSInteger)port {
    __block NSString *digest = nil;
    MUDatabasePerform(^{
        [self openDatabaseIfNeeded];
        FMResultSet *result = [db executeQuery:@"SELECT `digest` FROM `cert` WHERE `hostname` = ? AND `port` = ?",
                                     hostname, [NSNumber numberWithInteger:port]];
        if ([result next]) {
            digest = [result stringForColumnIndex:0];
        }
        [result close];
    });
    return digest;
}

#pragma mark -
#pragma mark Username rememberer

+ (void) storeUsername:(NSString *)username forServerWithHostname:(NSString *)hostname port:(NSInteger)port {
    MUDatabasePerform(^{
        [self openDatabaseIfNeeded];
        [db executeUpdate:@"REPLACE INTO `usernames` (`hostname`,`port`,`username`) VALUES (?,?,?)",
            hostname, [NSNumber numberWithInteger:port], username];
    });
}

+ (NSString *) usernameForServerWithHostname:(NSString *)hostname port:(NSInteger)port {
    __block NSString *username = nil;
    MUDatabasePerform(^{
        [self openDatabaseIfNeeded];
        FMResultSet *result = [db executeQuery:@"SELECT `username` FROM `usernames` WHERE `hostname` = ? AND `port` = ?",
                               hostname, [NSNumber numberWithInteger:port]];
        if ([result next]) {
            username = [result stringForColumnIndex:0];
        }
        [result close];
    });
    return username;
}

#pragma mark -
#pragma mark Access tokens

+ (void) storeAccessTokens:(NSArray *)tokens forServerWithHostname:(NSString *)hostname port:(NSInteger)port {
    NSData *tokensJSON = nil;
    if (tokens != nil) {
        NSError *err = nil;
        tokensJSON = [NSJSONSerialization dataWithJSONObject:tokens options:0 error:&err];
        if (err != nil) {
            NSLog(@"MUDatabase#storeAccessTokens:forServerWithHostname:port: %@", err);
            return;
        }
    }
    MUDatabasePerform(^{
        [self openDatabaseIfNeeded];
        [db executeUpdate:@"REPLACE INTO `tokens` (`hostname`,`port`,`tokens`) VALUES (?,?,?)",
            hostname, [NSNumber numberWithInteger:port], tokensJSON];
    });
}

+ (NSArray *) accessTokensForServerWithHostname:(NSString *)hostname port:(NSInteger)port {
    __block NSArray *tokens = nil;
    MUDatabasePerform(^{
        [self openDatabaseIfNeeded];
        FMResultSet *result = [db executeQuery:@"SELECT `tokens` FROM `tokens` WHERE `hostname` = ? AND `port` = ?",
                               hostname, [NSNumber numberWithInteger:port]];
        if ([result next]) {
            NSError *err = nil;
            NSData *tokensJSON = [result dataForColumnIndex:0];
            if (tokensJSON != nil) {
                tokens = [NSJSONSerialization JSONObjectWithData:tokensJSON options:0 error:&err];
                if (err != nil) {
                    NSLog(@"MUDatabase#accessTokensForServerWithHostname:port: %@", err);
                    tokens = nil;
                }
            }
        }
        [result close];
    });
    return tokens;
}

@end
