#import "MLClient.h"
// Copyright 2009-2010 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MUServerViewController.h"
#import "MUUserStateAcessoryView.h"
#import "MUNotificationController.h"
#import "MUColor.h"
#import "MUBackgroundView.h"
#import "MUServerTableViewCell.h"


#pragma mark -
#pragma mark MUChannelNavigationItem

@interface MUChannelNavigationItem : NSObject {
    id         _object;
    NSInteger  _indentLevel;
}

+ (MUChannelNavigationItem *) navigationItemWithObject:(id)obj indentLevel:(NSInteger)indentLevel;
- (id) initWithObject:(id)obj indentLevel:(NSInteger)indentLevel;
- (id) object;
- (NSInteger) indentLevel;
@end

@implementation MUChannelNavigationItem

+ (MUChannelNavigationItem *) navigationItemWithObject:(id)obj indentLevel:(NSInteger)indentLevel {
    return [[MUChannelNavigationItem alloc] initWithObject:obj indentLevel:indentLevel];
}

- (id) initWithObject:(id)obj indentLevel:(NSInteger)indentLevel {
    if (self = [super init]) {
        _object = obj;
        _indentLevel = indentLevel;
    }
    return self;
}

- (id) object {
    return _object;
}

- (NSInteger) indentLevel {
    return _indentLevel;
}

@end

#pragma mark -
#pragma mark MUChannelNavigationViewController

@interface MUServerViewController () {
    MUServerViewControllerViewMode   _viewMode;
    MLServerModel                    *_serverModel;
    NSMutableArray                   *_modelItems;
    NSMutableDictionary              *_userIndexMap;
    NSMutableDictionary              *_channelIndexMap;
    BOOL                             _pttState;
    UIButton                         *_talkButton;
}
- (NSInteger) indexForUser:(MLUser *)user;
- (void) reloadUser:(MLUser *)user;
- (void) reloadChannel:(MLChannel *)channel;
- (void) rebuildModelArrayFromChannel:(MLChannel *)channel;
- (void) addChannelTreeToModel:(MLChannel *)channel indentLevel:(NSInteger)indentLevel;
@end

@implementation MUServerViewController

#pragma mark -
#pragma mark Initialization and lifecycle

- (id) initWithServerModel:(MLServerModel *)serverModel {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _serverModel = serverModel;
        [_serverModel addDelegate:self];
        _viewMode = MUServerViewControllerViewModeServer;
    }
    return self;
}

- (void) dealloc {
    [_serverModel removeDelegate:self];
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if (@available(iOS 7, *)) {
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        self.tableView.separatorInset = UIEdgeInsetsZero;
    }
    
    if (_viewMode == MUServerViewControllerViewModeServer) {
        [self rebuildModelArrayFromChannel:[_serverModel rootChannel]];
        [self.tableView reloadData];
    } else if (_viewMode == MUServerViewControllerViewModeChannel) {
        [self switchToChannelMode];
        [self.tableView reloadData];
    }
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if ([[MLAudio sharedAudio] transmitType] == MLTransmitTypeToggle) {
        UIImage *onImage = [UIImage imageNamed:@"talkbutton_on"];
        UIImage *offImage = [UIImage imageNamed:@"talkbutton_off"];
        
        UIWindow *window = [[[UIApplication sharedApplication] windows] objectAtIndex:0];
        CGRect windowRect = [window frame];
        CGRect buttonRect = windowRect;
        buttonRect.size = onImage.size;
        buttonRect.origin.y = windowRect.size.height - (buttonRect.size.height + 40);
        buttonRect.origin.x = (windowRect.size.width - buttonRect.size.width)/2;
        
        _talkButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _talkButton.frame = buttonRect;
        [_talkButton setBackgroundImage:onImage forState:UIControlStateHighlighted];
        [_talkButton setBackgroundImage:offImage forState:UIControlStateNormal];
        [_talkButton setOpaque:NO];
        [_talkButton setAlpha:0.80f];
        [window addSubview:_talkButton];
        
        [_talkButton addTarget:self action:@selector(talkOn:) forControlEvents:UIControlEventTouchDown];
        [_talkButton addTarget:self action:@selector(talkOff:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(repositionTalkButton) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
        [self repositionTalkButton];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
}

- (void) viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if (_talkButton) {
        [_talkButton removeFromSuperview];
        _talkButton = nil;
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSInteger) indexForUser:(MLUser *)user {
    NSNumber *number = [_userIndexMap objectForKey:[NSNumber numberWithInteger:[user session]]];
    if (number) {
        return [number integerValue];
    }
    return NSNotFound;
}

- (NSInteger) indexForChannel:(MLChannel *)channel {
    NSNumber *number = [_channelIndexMap objectForKey:[NSNumber numberWithInteger:[channel channelId]]];
    if (number) {
        return [number integerValue];
    }
    return NSNotFound;
}

- (void) reloadUser:(MLUser *)user {
    NSInteger userIndex = [self indexForUser:user];
    if (userIndex != NSNotFound) {
        [[self tableView] reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:userIndex inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void) reloadChannel:(MLChannel *)channel {
    NSInteger idx = [self indexForChannel:channel];
    if (idx != NSNotFound) {
        [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:idx inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void) rebuildModelArrayFromChannel:(MLChannel *)channel {
    _modelItems = [[NSMutableArray alloc] init];

    _userIndexMap = [[NSMutableDictionary alloc] init];

    _channelIndexMap = [[NSMutableDictionary alloc] init];

    [self addChannelTreeToModel:channel indentLevel:0];
}

- (void) switchToServerMode {
    _viewMode = MUServerViewControllerViewModeServer;
    [self rebuildModelArrayFromChannel:[_serverModel rootChannel]];
}

- (void) switchToChannelMode {
    _viewMode = MUServerViewControllerViewModeChannel;

    _modelItems = [[NSMutableArray alloc] init];

    _userIndexMap = [[NSMutableDictionary alloc] init];

    _channelIndexMap = [[NSMutableDictionary alloc] init];
    
    MLChannel *channel = [[_serverModel connectedUser] channel];
    for (MLUser *user in [channel users]) {
        [_userIndexMap setObject:[NSNumber numberWithUnsignedInteger:[_modelItems count]] forKey:[NSNumber numberWithUnsignedInteger:[user session]]];
        [_modelItems addObject:[MUChannelNavigationItem navigationItemWithObject:user indentLevel:0]];
    }
}

- (void) addChannelTreeToModel:(MLChannel *)channel indentLevel:(NSInteger)indentLevel {
    [_channelIndexMap setObject:[NSNumber numberWithUnsignedInteger:[_modelItems count]] forKey:[NSNumber numberWithInteger:[channel channelId]]];
    [_modelItems addObject:[MUChannelNavigationItem navigationItemWithObject:channel indentLevel:indentLevel]];

    for (MLUser *user in [channel users]) {
        [_userIndexMap setObject:[NSNumber numberWithUnsignedInteger:[_modelItems count]] forKey:[NSNumber numberWithUnsignedInteger:[user session]]];
        [_modelItems addObject:[MUChannelNavigationItem navigationItemWithObject:user indentLevel:indentLevel+1]];
    }
    for (MLChannel *chan in [channel channels]) {
        [self addChannelTreeToModel:chan indentLevel:indentLevel+1];
    }
}

#pragma mark - Table view data source

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_modelItems count];
}

- (void) tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    MUChannelNavigationItem *navItem = [_modelItems objectAtIndex:[indexPath row]];
    id object = [navItem object];
    if ([object class] == [MLChannel class]) {
        MLChannel *chan = object;
        if (chan == [_serverModel rootChannel] && [_serverModel serverCertificatesTrusted]) {
            cell.backgroundColor = [MUColor verifiedCertificateChainColor];
        }
    }
}

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"ChannelNavigationCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        if (@available(iOS 7, *)) {
            cell = [[MUServerTableViewCell alloc] initWithReuseIdentifier:CellIdentifier];
        } else {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        }
    }

    MUChannelNavigationItem *navItem = [_modelItems objectAtIndex:[indexPath row]];
    id object = [navItem object];

    MLUser *connectedUser = [_serverModel connectedUser];

    cell.textLabel.font = [UIFont systemFontOfSize:18];
    if ([object class] == [MLChannel class]) {
        MLChannel *chan = object;
        cell.imageView.image = [UIImage imageNamed:@"channel"];
        cell.textLabel.text = [chan channelName];
        if (chan == [connectedUser channel])
            cell.textLabel.font = [UIFont boldSystemFontOfSize:18];
        cell.accessoryView = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        
    } else if ([object class] == [MLUser class]) {
        MLUser *user = object;

        cell.textLabel.text = [user userName];
        if (user == connectedUser)
            cell.textLabel.font = [UIFont boldSystemFontOfSize:18];
        
        MLTalkState talkState = [user talkState];
        NSString *talkImageName = nil;
        if (talkState == MLTalkStatePassive)
            talkImageName = @"talking_off";
        else if (talkState == MLTalkStateTalking)
            talkImageName = @"talking_on";
        else if (talkState == MLTalkStateWhispering)
            talkImageName = @"talking_whisper";
        else if (talkState == MLTalkStateShouting)
            talkImageName = @"talking_alt";
        
        // This check is here to correctly remove a user's talk state when backgrounding the app.
        //
        // For example, if the user of the app is holding his finger on the Push-to-Talk button
        // and decides to background Mumble while he is transmitting (via either the home- or
        // sleep button).
        //
        // This scenario brings two issues along with it:
        //
        //  1. We have to cut off Push-to-Talk when the app gets backgrounded - we get no TouchUpInside event
        //     from the UIButton, so we wouldn't regularly stop Push-to-Talk in this scenario.
        //
        //  2. Even if we set MLAudio's forceTransmit to NO, there exists a delay in the audio subsystem
        //     between setting the forceTransmit flag to NO before that change is propagated to MLServerModel
        //     delegates.
        //
        // The first problem is solved by registering a notification observer for when the app enters the
        // background. This is handled by the appDidEnterBackground: method of this class.
        //
        // This notification observer will set the forceTransmit flag to NO, but will also force-reload
        // the view controller's table view, causing us to enter this method soon before we're really backgrounded.
        //
        // That's fine, but because of problem #2, the user's talk state will most likely not be updated by the time
        // tableView:cellForRowAtIndexPath: is called by the table view.
        //
        // To solve this, we query the audio subsystem directly for the answer to whether the current user
        // should be treated as holding down Push-to-Talk, and therefore be listed with an active talk state
        // in the table view.
        if (user == connectedUser && [[MLAudio sharedAudio] transmitType] == MLTransmitTypeToggle) {
            if (![[MLAudio sharedAudio] forceTransmit]) {
                talkImageName = @"talking_off";
            }
        }
        
        cell.imageView.image = [UIImage imageNamed:talkImageName];
        cell.accessoryView = [MUUserStateAcessoryView viewForUser:user];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    cell.indentationLevel = [navItem indentLevel];

    return cell;
}

#pragma mark - Table view delegate

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    MUChannelNavigationItem *navItem = [_modelItems objectAtIndex:[indexPath row]];
    id object = [navItem object];
    if ([object class] == [MLChannel class]) {
        [_serverModel joinChannel:object];
    }

    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44.0f;
}

#pragma mark - MLServerModel delegate

- (void) serverModel:(MLServerModel *)model joinedServerAsUser:(MLUser *)user {
    [self rebuildModelArrayFromChannel:[model rootChannel]];
    [self.tableView reloadData];
}

- (void) serverModel:(MLServerModel *)model userJoined:(MLUser *)user {
}

- (void) serverModel:(MLServerModel *)model userDisconnected:(MLUser *)user {
}

- (void) serverModel:(MLServerModel *)model userLeft:(MLUser *)user {
    NSInteger idx = [self indexForUser:user];
    if (idx != NSNotFound) {
        if (_viewMode == MUServerViewControllerViewModeServer) {
            [self rebuildModelArrayFromChannel:[model rootChannel]];
        } else if (_viewMode) {
            [self switchToChannelMode];
        }
        [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:idx inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void) serverModel:(MLServerModel *)model userTalkStateChanged:(MLUser *)user {
    NSInteger userIndex = [self indexForUser:user];
    if (userIndex == NSNotFound) {
        return;
    }

    UITableViewCell *cell = [[self tableView] cellForRowAtIndexPath:[NSIndexPath indexPathForRow:userIndex inSection:0]];

    MLTalkState talkState = [user talkState];
    NSString *talkImageName = nil;
    if (talkState == MLTalkStatePassive)
        talkImageName = @"talking_off";
    else if (talkState == MLTalkStateTalking)
        talkImageName = @"talking_on";
    else if (talkState == MLTalkStateWhispering)
        talkImageName = @"talking_whisper";
    else if (talkState == MLTalkStateShouting)
        talkImageName = @"talking_alt";

    cell.imageView.image = [UIImage imageNamed:talkImageName];
}

- (void) serverModel:(MLServerModel *)model channelAdded:(MLChannel *)channel {
    if (_viewMode == MUServerViewControllerViewModeServer) {
        [self rebuildModelArrayFromChannel:[model rootChannel]];
        NSInteger idx = [self indexForChannel:channel];
        [self.tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:idx inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void) serverModel:(MLServerModel *)model channelRemoved:(MLChannel *)channel {
    if (_viewMode == MUServerViewControllerViewModeServer) {
        [self rebuildModelArrayFromChannel:[model rootChannel]];
        [self.tableView reloadData];
    } else if (_viewMode == MUServerViewControllerViewModeChannel) {
        [self switchToChannelMode];
        [self.tableView reloadData];
    }
}

- (void) serverModel:(MLServerModel *)model channelMoved:(MLChannel *)channel {
    if (_viewMode == MUServerViewControllerViewModeServer) {
        [self rebuildModelArrayFromChannel:[model rootChannel]];
        [self.tableView reloadData];
    }
}

- (void) serverModel:(MLServerModel *)model channelRenamed:(MLChannel *)channel {
    if (_viewMode == MUServerViewControllerViewModeServer) {
        [self reloadChannel:channel];
    }
}

- (void) serverModel:(MLServerModel *)model userMoved:(MLUser *)user toChannel:(MLChannel *)chan fromChannel:(MLChannel *)prevChan byUser:(MLUser *)mover {
    
    if (_viewMode == MUServerViewControllerViewModeServer) {
        [self.tableView beginUpdates];
        if (user == [model connectedUser]) {
            [self reloadChannel:chan];
            [self reloadChannel:prevChan];
        }
    
        // Check if the user is joining a channel for the first time.
        if (prevChan != nil) {
            NSInteger prevIdx = [self indexForUser:user];
            [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:prevIdx inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
        }

        [self rebuildModelArrayFromChannel:[model rootChannel]];
        NSInteger newIdx = [self indexForUser:user];
        [self.tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:newIdx inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
        [self.tableView endUpdates];
    } else if (_viewMode == MUServerViewControllerViewModeChannel) {
        NSInteger userIdx = [self indexForUser:user];
        MLChannel *curChan = [[_serverModel connectedUser] channel];
        
        if (user == [model connectedUser]) {
            [self switchToChannelMode];
            [self.tableView reloadData];
        } else {
            // User is leaving
            [self.tableView beginUpdates];
            if (prevChan == curChan && userIdx != NSNotFound) {
                [self switchToChannelMode];
                [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:userIdx inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
                // User is joining
            } else if (chan == curChan && userIdx == NSNotFound) {
                [self switchToChannelMode];
                userIdx = [self indexForUser:user];
                if (userIdx != NSNotFound) {
                    [self.tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:userIdx inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
                }
            }
            [self.tableView endUpdates];
        }
    }
}

- (void) serverModel:(MLServerModel *)model userSelfMuted:(MLUser *)user {
}

- (void) serverModel:(MLServerModel *)model userRemovedSelfMute:(MLUser *)user {
}

- (void) serverModel:(MLServerModel *)model userSelfMutedAndDeafened:(MLUser *)user {
}

- (void) serverModel:(MLServerModel *)model userRemovedSelfMuteAndDeafen:(MLUser *)user {
}

- (void) serverModel:(MLServerModel *)model userSelfMuteDeafenStateChanged:(MLUser *)user {
    [self reloadUser:user];
}

// --

- (void) serverModel:(MLServerModel *)model userMutedAndDeafened:(MLUser *)user byUser:(MLUser *)actor {
    [self reloadUser:user];
}

- (void) serverModel:(MLServerModel *)model userUnmutedAndUndeafened:(MLUser *)user byUser:(MLUser *)actor {
    [self reloadUser:user];
}

- (void) serverModel:(MLServerModel *)model userMuted:(MLUser *)user byUser:(MLUser *)actor {
    [self reloadUser:user];
}

- (void) serverModel:(MLServerModel *)model userUnmuted:(MLUser *)user byUser:(MLUser *)actor {
    [self reloadUser:user];
}

- (void) serverModel:(MLServerModel *)model userDeafened:(MLUser *)user byUser:(MLUser *)actor {
    [self reloadUser:user];
}

- (void) serverModel:(MLServerModel *)model userUndeafened:(MLUser *)user byUser:(MLUser *)actor {
    [self reloadUser:user];
}

- (void) serverModel:(MLServerModel *)model userSuppressed:(MLUser *)user byUser:(MLUser *)actor {
    [self reloadUser:user];
}

- (void) serverModel:(MLServerModel *)model userUnsuppressed:(MLUser *)user byUser:(MLUser *)actor {
    [self reloadUser:user];
}

- (void) serverModel:(MLServerModel *)model userMuteStateChanged:(MLUser *)user {
   [self reloadUser:user];
}

- (void) serverModel:(MLServerModel *)model userAuthenticatedStateChanged:(MLUser *)user {
    [self reloadUser:user];
}

- (void) serverModel:(MLServerModel *)model userPrioritySpeakerChanged:(MLUser *)user {
    [self reloadUser:user];
}

#pragma mark - PushToTalk

- (void) repositionTalkButton {
    // fixme(mkrautz): This should stay put if we're run on the iPhone.
    return;
    
    UIDevice *device = [UIDevice currentDevice];
    UIWindow *window = [[[UIApplication sharedApplication] windows] objectAtIndex:0];
    CGRect windowRect = window.frame;
    CGRect buttonRect;
    CGSize buttonSize;
    
    UIImage *onImage = [UIImage imageNamed:@"talkbutton_on"];
    buttonRect.size = onImage.size;
    buttonRect.origin = CGPointMake(0, 0);
    _talkButton.transform = CGAffineTransformIdentity;
    buttonSize = onImage.size;
    buttonRect.size = buttonSize;
    
    
    UIDeviceOrientation orientation = device.orientation;
    if (orientation == UIDeviceOrientationLandscapeLeft) {
        _talkButton.transform = CGAffineTransformMakeRotation(M_PI_2);
        buttonRect = _talkButton.frame;
        buttonRect.origin.y = (windowRect.size.height - buttonSize.width)/2;
        buttonRect.origin.x = 40;
        _talkButton.frame = buttonRect;
    } else if (orientation == UIDeviceOrientationLandscapeRight) {
        _talkButton.transform = CGAffineTransformMakeRotation(-M_PI_2);
        buttonRect = _talkButton.frame;
        buttonRect.origin.y = (windowRect.size.height - buttonSize.width)/2;
        buttonRect.origin.x = windowRect.size.width - (buttonSize.height + 40);
        _talkButton.frame = buttonRect;
    } else if (orientation == UIDeviceOrientationPortrait) {
        _talkButton.transform = CGAffineTransformMakeRotation(0.0f);
        buttonRect = _talkButton.frame;
        buttonRect.origin.y = windowRect.size.height - (buttonSize.height + 40);
        buttonRect.origin.x = (windowRect.size.width - buttonSize.width)/2;
        _talkButton.frame = buttonRect;
    } else if (orientation == UIDeviceOrientationPortraitUpsideDown) {
        _talkButton.transform = CGAffineTransformMakeRotation(M_PI);
        buttonRect = _talkButton.frame;
        buttonRect.origin.y = 40;
        buttonRect.origin.x = (windowRect.size.width - buttonSize.width)/2;
        _talkButton.frame = buttonRect;
    }
}

- (void) talkOn:(UIButton *)button {
    [button setAlpha:1.0f];
    [[MLAudio sharedAudio] setForceTransmit:YES];
}

- (void) talkOff:(UIButton *)button {
    [button setAlpha:0.80f];
    [[MLAudio sharedAudio] setForceTransmit:NO];
}

#pragma mark - Mode switch

- (void) toggleMode {
    if (_viewMode == MUServerViewControllerViewModeServer) {
        NSString *msg = NSLocalizedString(@"Switched to channel view mode.", nil);
        [[MUNotificationController sharedController] addNotification:msg];
        [self switchToChannelMode];
    } else if (_viewMode == MUServerViewControllerViewModeChannel) {
        NSString *msg = NSLocalizedString(@"Switched to server view mode.", nil);
        [[MUNotificationController sharedController] addNotification:msg];
        [self switchToServerMode];
    }

    [self.tableView reloadData];
    
    if (_viewMode == MUServerViewControllerViewModeServer) {
        MLChannel *cur = [[_serverModel connectedUser] channel];
        NSInteger idx = [self indexForChannel:cur];
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:idx inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
    }
}

#pragma mark - Background notification

- (void) appDidEnterBackground:(NSNotification *)notification {
    // Force Push-to-Talk to stop when the app is backgrounded.
    [[MLAudio sharedAudio] setForceTransmit:NO];
    
    // Reload the table view to re-render the talk state for the user
    // as not talking if they were holding down their Push-to-Talk buttons
    // at the moment the app was sent to the background.
    [[self tableView] reloadData];
}

@end

