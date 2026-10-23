// Copyright 2009-2012 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MUMessageRecipientViewController.h"
#import "MUUserStateAcessoryView.h"
#import "MUColor.h"
#import "MUBackgroundView.h"
#import "MUServerTableViewCell.h"

@interface MUMessageRecipientViewController () {
    MLServerModel                                 *_serverModel;
    NSMutableArray                                *_modelItems;
    NSMutableDictionary                           *_userIndexMap;
    NSMutableDictionary                           *_channelIndexMap;
    id<MUMessageRecipientViewControllerDelegate>  _delegate;
}
- (void) rebuildModelArrayFromChannel:(MLChannel *)channel;
- (void) addChannelTreeToModel:(MLChannel *)channel indentLevel:(NSInteger)indentLevel;
@end

@implementation MUMessageRecipientViewController

- (id) initWithServerModel:(MLServerModel *)model {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _serverModel = model;
        [_serverModel addDelegate:self];
    }
    return self;
}

- (void) dealloc {
    [_serverModel removeDelegate:self];
}

- (id<MUMessageRecipientViewControllerDelegate>) delegate {
    return _delegate;
}

- (void) setDelegate:(id<MUMessageRecipientViewControllerDelegate>)delegate {
    _delegate = delegate;
}

- (void) rebuildModelArrayFromChannel:(MLChannel *)channel {
    _modelItems = [[NSMutableArray alloc] init];

    _userIndexMap = [[NSMutableDictionary alloc] init];

    _channelIndexMap = [[NSMutableDictionary alloc] init];
    
    [self addChannelTreeToModel:channel indentLevel:0];
}

- (void) addChannelTreeToModel:(MLChannel *)channel indentLevel:(NSInteger)indentLevel {
    [_channelIndexMap setObject:[NSNumber numberWithUnsignedInteger:[_modelItems count]] forKey:[NSNumber numberWithUnsignedInteger:[channel channelId]]];
    [_modelItems addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:indentLevel], @"indentLevel", channel, @"object", nil]];
    
    for (MLUser *user in [channel users]) {
        [_userIndexMap setObject:[NSNumber numberWithUnsignedInteger:[_modelItems count]] forKey:[NSNumber numberWithUnsignedInteger:[user session]]];
        [_modelItems addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:indentLevel+1], @"indentLevel", user, @"object", nil]];
    }
    for (MLChannel *chan in [channel channels]) {
        [self addChannelTreeToModel:chan indentLevel:indentLevel+1];
    }
}

- (NSInteger) indexForUser:(MLUser *)user {
    NSInteger userIndex = 1+[[_userIndexMap objectForKey:[NSNumber numberWithUnsignedInteger:[user session]]] integerValue];
    return userIndex;
}

- (NSInteger) indexForChannel:(MLChannel *)channel {
    NSInteger channelIndex = 1+[[_channelIndexMap objectForKey:[NSNumber numberWithUnsignedInteger:[channel channelId]]] integerValue];
    return channelIndex;
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

#pragma mark - View lifecycle

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    self.navigationItem.title = NSLocalizedString(@"Message Recipient", nil);
    
    if (@available(iOS 7, *)) {
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        self.tableView.separatorInset = UIEdgeInsetsZero;
    }

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelClicked:)];
    
    [self rebuildModelArrayFromChannel:[_serverModel rootChannel]];
    [self.tableView reloadData];
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void) viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

- (void) viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
}

#pragma mark - Table view data source

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1 + [_modelItems count];
}

- (void) tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([indexPath row] == 0)
        return;
    NSDictionary *dict = [_modelItems objectAtIndex:[indexPath row]-1];
    id object = [dict objectForKey:@"object"];
    if ([object class] == [MLChannel class]) {
        MLChannel *channel = (MLChannel *) object;
        if (channel == [_serverModel rootChannel] && [_serverModel serverCertificatesTrusted]) {
            cell.backgroundColor = [MUColor verifiedCertificateChainColor];
        }
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"MUMessageRecipientCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        if (@available(iOS 7, *)) {
            cell = [[MUServerTableViewCell alloc] initWithReuseIdentifier:CellIdentifier];
        } else {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        }
    }

    cell.textLabel.font = [UIFont systemFontOfSize:18.0f];
    cell.selectionStyle = UITableViewCellSelectionStyleGray;

    if ([indexPath row] == 0) {
        [[cell imageView] setImage:[UIImage imageNamed:@"channel"]];
        [[cell textLabel] setText:NSLocalizedString(@"Current Channel", nil)];
        [[cell textLabel] setFont:[UIFont boldSystemFontOfSize:18.0f]];
        [cell setIndentationLevel:0];
        [cell setAccessoryView:nil];
    } else {
        NSDictionary *dict = [_modelItems objectAtIndex:[indexPath row]-1];
        id object = [dict objectForKey:@"object"];
        NSInteger indentLevel = [[dict objectForKey:@"indentLevel"] integerValue];
        if ([object class] == [MLChannel class]) {
            MLChannel *channel = (MLChannel *) object;
            if ([[_serverModel connectedUser] channel] == channel) {
                [[cell textLabel] setFont:[UIFont boldSystemFontOfSize:18.0f]];
            } else {
                [[cell textLabel] setFont:[UIFont systemFontOfSize:18.0f]];    
            }
            [[cell imageView] setImage:[UIImage imageNamed:@"channel"]];
            [[cell textLabel] setText:[channel channelName]];
            [cell setIndentationLevel:indentLevel];
            [cell setAccessoryView:nil];
        } else if ([object class] == [MLUser class]) {
            MLUser *user = (MLUser *) object;
            if (user == [_serverModel connectedUser]) {
                [[cell textLabel] setFont:[UIFont boldSystemFontOfSize:18.0f]];
            } else {
                [[cell textLabel] setFont:[UIFont systemFontOfSize:18.0f]];    
            }
            [[cell textLabel] setText:[user userName]];
            [cell setIndentationLevel:indentLevel];
            
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
            [[cell imageView] setImage:[UIImage imageNamed:talkImageName]];

            [cell setAccessoryView:[MUUserStateAcessoryView viewForUser:user]];
        }
    }
    
    return cell;
}

#pragma mark - Table view delegate

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([indexPath row] == 0) {
        [_delegate messageRecipientViewControllerDidSelectCurrentChannel:self];
    } else {
        NSDictionary *dict = [_modelItems objectAtIndex:[indexPath row]-1];
        id object = [dict objectForKey:@"object"];
        if ([object class] == [MLChannel class]) {
            [_delegate messageRecipientViewController:self didSelectChannel:object];
        } else if ([object class] == [MLUser class]) {
            [_delegate messageRecipientViewController:self didSelectUser:object];
        }
    }

    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Actions

- (void) cancelClicked:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
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
    [self rebuildModelArrayFromChannel:[model rootChannel]];
    [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:idx inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void) serverModel:(MLServerModel *)model userTalkStateChanged:(MLUser *)user {
    NSInteger userIndex = [self indexForUser:user];
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
    [self rebuildModelArrayFromChannel:[model rootChannel]];
    NSInteger idx = [self indexForChannel:channel];
    [self.tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:idx inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void) serverModel:(MLServerModel *)model channelRemoved:(MLChannel *)channel {
    [self rebuildModelArrayFromChannel:[model rootChannel]];
    [self.tableView reloadData];
}

- (void) serverModel:(MLServerModel *)model channelMoved:(MLChannel *)channel {
    [self rebuildModelArrayFromChannel:[model rootChannel]];
    [self.tableView reloadData];
}

- (void) serverModel:(MLServerModel *)model channelRenamed:(MLChannel *)channel {
    [self reloadChannel:channel];
}

- (void) serverModel:(MLServerModel *)model userMoved:(MLUser *)user toChannel:(MLChannel *)chan fromChannel:(MLChannel *)prevChan byUser:(MLUser *)mover {
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

@end
