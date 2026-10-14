// Copyright 2009-2026 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by the BSD-style license in LICENSE.

#import "MUWelcomeScreenPhone.h"
#import "MUPublicServerListController.h"
#import "MUFavouriteServerListController.h"
#import "MULanServerListController.h"
#import "MUConnectionController.h"
#import "MUDatabase.h"
#import "MUFavouriteServer.h"

static const NSUInteger MUHomeServerPreviewLimit = 5;

@interface MUWelcomeScreenPhone () {
    NSArray<MUFavouriteServer *> *_favouriteServers;
    NSArray<NSNetService *> *_lanServices;
    MULanServerListController *_lanDiscovery;
    BOOL _favouritesExpanded, _lanExpanded, _homeVisible, _loadingFavourites, _lanDiscoveryFailed;
    NSUInteger _favouritesGeneration;
    BOOL _rowUpdateInProgress, _pendingLANRefresh, _startLANAfterUpdate;
    NSArray<MUFavouriteServer *> *_pendingFavourites;
    NSMutableIndexSet *_pendingToggles;
}
@end

@implementation MUWelcomeScreenPhone

- (id)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _favouriteServers = @[];
        _lanServices = @[];
        _favouritesExpanded = YES;
        _pendingToggles = [NSMutableIndexSet indexSet];
        self.title = NSLocalizedString(@"Home", nil);
        self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeInline;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundView = nil;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appEnteredBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appBecameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    _lanDiscovery.serversChangedHandler = nil;
    [_lanDiscovery stopDiscovery];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _homeVisible = YES;
    self.navigationController.toolbarHidden = YES;
    self.navigationItem.leftBarButtonItem = nil;
    self.navigationItem.rightBarButtonItem = nil;
    [self reloadFavourites];
    [self.tableView reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_lanExpanded) [self startLANDiscovery];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _homeVisible = NO;
    ++_favouritesGeneration;
    [_pendingToggles removeAllIndexes];
    _pendingFavourites = nil;
    _pendingLANRefresh = NO;
    [_lanDiscovery stopDiscovery];
}

- (void)appEnteredBackground:(NSNotification *)notification { [_lanDiscovery stopDiscovery]; }
- (void)appBecameActive:(NSNotification *)notification {
    if (_homeVisible && _lanExpanded) [self startLANDiscovery];
}

- (void)reloadFavourites {
    NSUInteger generation = ++_favouritesGeneration;
    _loadingFavourites = YES;
    __weak MUWelcomeScreenPhone *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *servers = [[MUDatabase fetchAllFavourites] sortedArrayUsingSelector:@selector(compare:)];
        dispatch_async(dispatch_get_main_queue(), ^{
            MUWelcomeScreenPhone *controller = weakSelf;
            if (!controller || !controller->_homeVisible || generation != controller->_favouritesGeneration) return;
            controller->_pendingFavourites = servers;
            [controller drainPendingUpdates];
        });
    });
}

- (void)startLANDiscovery {
    if (!_homeVisible || !_lanExpanded || UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) return;
    if (!_lanDiscovery) {
        _lanDiscovery = [MULanServerListController new];
        __weak MUWelcomeScreenPhone *weakSelf = self;
        _lanDiscovery.serversChangedHandler = ^{
            MUWelcomeScreenPhone *controller = weakSelf;
            if (!controller || !controller->_homeVisible || !controller->_lanExpanded) return;
            controller->_pendingLANRefresh = YES;
            [controller drainPendingUpdates];
        };
    }
    [_lanDiscovery startDiscovery];
}

- (void)drainPendingUpdates {
    if (_rowUpdateInProgress || !_homeVisible) return;
    if (_pendingToggles.count) {
        NSUInteger section = _pendingToggles.firstIndex;
        [_pendingToggles removeIndex:section];
        [self toggleSection:section];
    } else if (_pendingFavourites) {
        NSArray *servers = _pendingFavourites;
        _pendingFavourites = nil;
        [self updatePreviewSection:0 changes:^{
            self->_favouriteServers = servers;
            self->_loadingFavourites = NO;
        }];
    } else if (_pendingLANRefresh) {
        _pendingLANRefresh = NO;
        if (!_lanExpanded) return;
        NSArray *services = _lanDiscovery.discoveredServers;
        BOOL failed = _lanDiscovery.discoveryFailed;
        if (!services.count && !_lanServices.count && failed == _lanDiscoveryFailed) return;
        [self updatePreviewSection:2 changes:^{
            self->_lanServices = services;
            self->_lanDiscoveryFailed = failed;
        }];
    }
}

- (void)finishRowUpdate {
    _rowUpdateInProgress = NO;
    BOOL startLAN = _startLANAfterUpdate;
    _startLANAfterUpdate = NO;
    if (!_homeVisible) return;
    // Browsing begins after expansion, so the initial results cannot interrupt it.
    if (startLAN && _lanExpanded && ![_pendingToggles containsIndex:2]) [self startLANDiscovery];
    [self drainPendingUpdates];
}

- (void)updatePreviewSection:(NSInteger)section changes:(dispatch_block_t)changes {
    BOOL expanded = section == 0 ? _favouritesExpanded : _lanExpanded;
    if (!expanded || !self.view.window) {
        changes();
        if (!self.view.window) [self.tableView reloadData];
        [self drainPendingUpdates];
        return;
    }
    NSInteger oldRows = [self.tableView numberOfRowsInSection:section];
    _rowUpdateInProgress = YES;
    __block NSInteger newRows;
    [UIView performWithoutAnimation:^{
        [self.tableView performBatchUpdates:^{
            changes();
            newRows = [self tableView:self.tableView numberOfRowsInSection:section];
            NSMutableArray *paths = [NSMutableArray array];
            for (NSInteger row = MIN(oldRows, newRows) - 1; row < MAX(oldRows, newRows) - 1; ++row)
                [paths addObject:[NSIndexPath indexPathForRow:row inSection:section]];
            if (newRows > oldRows) [self.tableView insertRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
            else if (newRows < oldRows) [self.tableView deleteRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
        } completion:^(BOOL finished) {
            if (self->_homeVisible && self.view.window) {
                NSMutableArray *body = [NSMutableArray array];
                for (NSInteger row = 1; row < newRows - 1; ++row) [body addObject:[NSIndexPath indexPathForRow:row inSection:section]];
                [UIView performWithoutAnimation:^{ [self.tableView reconfigureRowsAtIndexPaths:body]; }];
            }
            [self finishRowUpdate];
        }];
    }];
}

- (void)toggleSection:(NSInteger)section {
    if (_rowUpdateInProgress) {
        if ([_pendingToggles containsIndex:section]) [_pendingToggles removeIndex:section];
        else [_pendingToggles addIndex:section];
        return;
    }
    BOOL expanded = !(section == 0 ? _favouritesExpanded : _lanExpanded);
    NSInteger bodyRows = 1 + MAX(1, [self previewCountForSection:section]);
    NSMutableArray *paths = [NSMutableArray array];
    for (NSInteger row = 1; row <= bodyRows; ++row) [paths addObject:[NSIndexPath indexPathForRow:row inSection:section]];
    _rowUpdateInProgress = YES;
    [self.tableView performBatchUpdates:^{
        if (section == 0) self->_favouritesExpanded = expanded;
        else {
            self->_lanExpanded = expanded;
            self->_startLANAfterUpdate = expanded;
            if (!expanded) {
                [self->_lanDiscovery stopDiscovery];
                self->_lanServices = @[];
                self->_pendingLANRefresh = NO;
            }
        }
        UITableViewRowAnimation animation = UIAccessibilityIsReduceMotionEnabled() ? UITableViewRowAnimationNone : UITableViewRowAnimationFade;
        if (expanded) [self.tableView insertRowsAtIndexPaths:paths withRowAnimation:animation];
        else [self.tableView deleteRowsAtIndexPaths:paths withRowAnimation:animation];
    } completion:^(BOOL finished) { [self finishRowUpdate]; }];
    UITableViewCell *category = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]];
    category.accessibilityValue = expanded ? NSLocalizedString(@"Expanded", nil) : NSLocalizedString(@"Collapsed", nil);
    UIView *chevron = category.accessoryView.subviews.firstObject;
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : .25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
        chevron.transform = CGAffineTransformMakeRotation(expanded ? M_PI : 0);
    } completion:nil];
}

- (NSUInteger)previewCountForSection:(NSInteger)section {
    return MIN(MUHomeServerPreviewLimit, section == 0 ? _favouriteServers.count : _lanServices.count);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    BOOL expanded = section == 0 ? _favouritesExpanded : _lanExpanded;
    if (section == 1 || !expanded) return 1;
    // Category, up to five servers (or an empty state), and the full-list entry.
    return 2 + MAX(1, [self previewCountForSection:section]);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"homeServerItem"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"homeServerItem"];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessibilityTraits = UIAccessibilityTraitButton;
    cell.accessibilityValue = nil;
    cell.userInteractionEnabled = YES;
    UIListContentConfiguration *content;
    if (indexPath.row == 0) {
        content = [UIListContentConfiguration cellConfiguration];
        NSArray *titles = @[NSLocalizedString(@"Favourite Servers", nil), NSLocalizedString(@"Public Servers", nil), NSLocalizedString(@"LAN Servers", nil)];
        content.text = titles[indexPath.section];
        content.image = [UIImage systemImageNamed:@[@"star", @"globe", @"wifi"][indexPath.section]];
        content.imageProperties.reservedLayoutSize = CGSizeMake(28, 28);
        if (indexPath.section == 1) cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        else {
            BOOL expanded = indexPath.section == 0 ? _favouritesExpanded : _lanExpanded;
            UIView *accessory = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
            UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down"]];
            chevron.frame = accessory.bounds;
            chevron.contentMode = UIViewContentModeScaleAspectFit;
            chevron.transform = CGAffineTransformMakeRotation(expanded ? M_PI : 0);
            chevron.tintColor = UIColor.tertiaryLabelColor;
            [accessory addSubview:chevron];
            cell.accessoryView = accessory;
            cell.accessibilityValue = expanded ? NSLocalizedString(@"Expanded", nil) : NSLocalizedString(@"Collapsed", nil);
        }
    } else {
        NSUInteger count = [self previewCountForSection:indexPath.section];
        BOOL fullListEntry = indexPath.row == MAX(1, count) + 1;
        if (fullListEntry) {
            content = [UIListContentConfiguration cellConfiguration];
            content.text = indexPath.section == 0 ? NSLocalizedString(@"Manage Favourites", nil) : NSLocalizedString(@"Show All", nil);
            content.textProperties.color = UIColor.linkColor;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (count == 0) {
            content = [UIListContentConfiguration cellConfiguration];
            content.text = indexPath.section == 0 ? (_loadingFavourites ? NSLocalizedString(@"Loading…", nil) : NSLocalizedString(@"No favourite servers", nil))
                : (_lanDiscoveryFailed ? NSLocalizedString(@"LAN discovery unavailable", nil) : NSLocalizedString(@"No LAN servers found", nil));
            content.textProperties.color = UIColor.secondaryLabelColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessibilityTraits = UIAccessibilityTraitStaticText;
            cell.userInteractionEnabled = NO;
        } else {
            content = [UIListContentConfiguration subtitleCellConfiguration];
            if (indexPath.section == 0) {
                MUFavouriteServer *server = _favouriteServers[indexPath.row - 1];
                content.text = server.displayName.length ? server.displayName : server.hostName;
                content.secondaryText = [NSString stringWithFormat:@"%@:%lu", server.hostName, (unsigned long)server.port];
            } else {
                NSNetService *server = _lanServices[indexPath.row - 1];
                content.text = server.name;
                content.secondaryText = server.hostName.length ? [NSString stringWithFormat:@"%@:%ld", server.hostName, (long)server.port] : NSLocalizedString(@"Resolving…", nil);
            }
            content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(12, 52, 12, 16);
    }
    cell.contentConfiguration = content;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        [self.navigationController pushViewController:[MUPublicServerListController new] animated:YES];
    } else if (indexPath.row == 0) {
        [self toggleSection:indexPath.section];
    } else if (indexPath.row == MAX(1, [self previewCountForSection:indexPath.section]) + 1) {
        UIViewController *list = indexPath.section == 0 ? [MUFavouriteServerListController new] : [MULanServerListController new];
        [self.navigationController pushViewController:list animated:YES];
    } else if (indexPath.section == 0 && indexPath.row <= [self previewCountForSection:0]) {
        MUFavouriteServer *server = _favouriteServers[indexPath.row - 1];
        [[MUConnectionController sharedController] connectToFavouriteServer:server withParentViewController:self];
    } else if (indexPath.section == 2 && indexPath.row <= [self previewCountForSection:2]) {
        [_lanDiscovery presentActionsForServer:_lanServices[indexPath.row - 1] fromViewController:self sourceView:[tableView cellForRowAtIndexPath:indexPath]];
    }
}


@end
