// Copyright 2009-2011 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MUServerRootViewController.h"
#import "MUApplicationDelegate.h"
#import "MUServerViewController.h"
#import "MUServerCertificateTrustViewController.h"
#import "MUAccessTokenViewController.h"
#import "MUCertificateViewController.h"
#import "MUNotificationController.h"
#import "MUConnectionController.h"
#import "MUMessagesViewController.h"
#import "MUDatabase.h"

#import "MLClient.h"


@interface MUServerRootViewController () <MLConnectionDelegate, MLServerModelDelegate> {
    MLConnection                *_connection;
    MLServerModel               *_model;
    
    NSInteger                   _segmentIndex;
    UISegmentedControl          *_segmentedControl;
    UIBarButtonItem             *_menuButton;
    UIBarButtonItem             *_disconnectButton;

    MUServerViewController      *_serverView;
    MUMessagesViewController    *_messagesView;
    
    NSInteger                   _unreadMessages;
}
- (NSArray<UIMenuElement *> *)serverMenuActions;
@end

@implementation MUServerRootViewController

- (id) initWithConnection:(MLConnection *)conn andServerModel:(MLServerModel *)model {
    if ((self = [super init])) {
        _connection = conn;
        _model = model;
        [_model addDelegate:self];
        
        _unreadMessages = 0;
        
        _serverView = [[MUServerViewController alloc] initWithServerModel:_model];
        _messagesView = [[MUMessagesViewController alloc] initWithServerModel:_model];
        

    }
    return self;
}

- (void) dealloc {
    [_model removeDelegate:self];
    [_connection setDelegate:nil];
}

- (void) takeOwnershipOfConnectionDelegate {
    [_connection setDelegate:self];
}

#pragma mark - View lifecycle

- (void) viewDidLoad {
    [super viewDidLoad];

    _segmentedControl = [[UISegmentedControl alloc] initWithItems:
                         [NSArray arrayWithObjects:
                            NSLocalizedString(@"Server", nil),
                            NSLocalizedString(@"Messages", nil),
                          nil]];
    
    _segmentIndex = 0;
    
    _segmentedControl.selectedSegmentIndex = _segmentIndex;
    [_segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    
    __weak MUServerRootViewController *weakSelf = self;
    UIDeferredMenuElement *actions = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        completion([weakSelf serverMenuActions] ?: @[]);
    }];
    _menuButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:[UIMenu menuWithChildren:@[actions]]];
    _menuButton.accessibilityLabel = NSLocalizedString(@"Server", nil);
    
    UIImageSymbolConfiguration *barIcon = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium];
    _disconnectButton = [self barButtonWithImage:[[UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:barIcon] imageWithTintColor:[UIColor systemRedColor] renderingMode:UIImageRenderingModeAlwaysOriginal] action:@selector(disconnectButtonClicked:)];
    _disconnectButton.accessibilityLabel = NSLocalizedString(@"Disconnect", nil);
    
    [_segmentedControl sizeToFit];
    CGRect segmentFrame = _segmentedControl.frame;
    segmentFrame.size.width = MAX(segmentFrame.size.width, 200.0f);
    segmentFrame.size.height = 32.0f;
    _segmentedControl.frame = segmentFrame;
    [self updateUnreadMessageCount];

    
    [self applyNavigationItemsToViewController:_serverView];
    
    [self setViewControllers:[NSArray arrayWithObject:_serverView] animated:NO];

    self.toolbar.barStyle = UIBarStyleDefault;
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (UIInterfaceOrientationMask) supportedInterfaceOrientations {
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        return UIInterfaceOrientationMaskAll;
    }
    return UIInterfaceOrientationMaskPortrait;
}

- (UIBarButtonItem *)barButtonWithImage:(UIImage *)image action:(SEL)action {
    return [[UIBarButtonItem alloc] initWithImage:image style:UIBarButtonItemStylePlain target:self action:action];
}

- (void) applyNavigationItemsToViewController:(UIViewController *)controller {
    controller.navigationItem.titleView = _segmentedControl;
    controller.navigationItem.leftBarButtonItem = _disconnectButton;
    controller.navigationItem.rightBarButtonItem = _menuButton;
}

- (void) disconnectButtonClicked:(id)sender {
    UIAlertController *alertCtrl = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Disconnect", nil)
                                                                       message:NSLocalizedString(@"Leave this server?", nil)
                                                                preferredStyle:UIAlertControllerStyleAlert];
    [alertCtrl addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
    [alertCtrl addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Disconnect", nil)
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *action) {
        [[MUConnectionController sharedController] disconnectFromServer];
    }]];
    UIViewController *presenter = [self visibleViewController];
    if (presenter == nil) {
        presenter = self;
    }
    [presenter presentViewController:alertCtrl animated:YES completion:nil];
}

- (void) segmentChanged:(id)sender {
    if (_segmentedControl.selectedSegmentIndex == 0) { // Server view
        [self applyNavigationItemsToViewController:_serverView];
        [self setViewControllers:[NSArray arrayWithObject:_serverView] animated:NO];
    } else if (_segmentedControl.selectedSegmentIndex == 1) { // Messages view
        [self applyNavigationItemsToViewController:_messagesView];
        [self setViewControllers:[NSArray arrayWithObject:_messagesView] animated:NO];
    }
    
    if (_segmentedControl.selectedSegmentIndex == 1) { // Messages view
        _unreadMessages = 0;
        [self updateUnreadMessageCount];
        [MUApplicationDelegate setApplicationBadgeCount:0];
    }


    [[MLAudio sharedAudio] setForceTransmit:NO];
}

#pragma mark - MLConnection delegate

- (void) connectionOpened:(MLConnection *)conn {
}

- (void) connection:(MLConnection *)conn rejectedWithReason:(MLRejectReason)reason explanation:(NSString *)explanation {
}

- (void) connection:(MLConnection *)conn trustFailureInCertificateChain:(NSArray *)chain {
}

- (void) connection:(MLConnection *)conn unableToConnectWithError:(NSError *)err {
}

- (void) connection:(MLConnection *)conn closedWithError:(NSError *)err {
    if (err) {
        UIAlertController *alertCtrl = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Connection closed", nil)
                                                                           message:[err localizedDescription]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
        [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                       style:UIAlertActionStyleCancel
                                                     handler:nil]];
        
        [self presentViewController:alertCtrl animated:YES completion:nil];

        [[MUConnectionController sharedController] disconnectFromServer];
    }
}

#pragma mark - MLServerModel delegate

- (void) serverModel:(MLServerModel *)model userKicked:(MLUser *)user byUser:(MLUser *)actor forReason:(NSString *)reason {
    if (user == [model connectedUser]) {
        NSString *reasonMsg = reason ? reason : NSLocalizedString(@"(No reason)", nil);
        NSString *title = NSLocalizedString(@"You were kicked", nil);
        NSString *alertMsg = [NSString stringWithFormat:
                                NSLocalizedString(@"Kicked by %@ for reason: \"%@\"", @"Kicked by user for reason"),
                                    [actor userName], reasonMsg];
        
        UIAlertController *alertCtrl = [UIAlertController alertControllerWithTitle:title
                                                                           message:alertMsg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
        [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                       style:UIAlertActionStyleCancel
                                                     handler:nil]];
        
        [self presentViewController:alertCtrl animated:YES completion:nil];
        
        [[MUConnectionController sharedController] disconnectFromServer];
    }
}

- (void) serverModel:(MLServerModel *)model userBanned:(MLUser *)user byUser:(MLUser *)actor forReason:(NSString *)reason {
    if (user == [model connectedUser]) {
        NSString *reasonMsg = reason ? reason : NSLocalizedString(@"(No reason)", nil);
        NSString *title = NSLocalizedString(@"You were banned", nil);
        NSString *alertMsg = [NSString stringWithFormat:
                                NSLocalizedString(@"Banned by %@ for reason: \"%@\"", nil),
                                    [actor userName], reasonMsg];
        
        UIAlertController *alertCtrl = [UIAlertController alertControllerWithTitle:title
                                                                           message:alertMsg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
        [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                       style:UIAlertActionStyleCancel
                                                     handler:nil]];
        
        [self presentViewController:alertCtrl animated:YES completion:nil];
        
        [[MUConnectionController sharedController] disconnectFromServer];
    }
}

- (void) serverModel:(MLServerModel *)model permissionDenied:(MLPermission)perm forUser:(MLUser *)user inChannel:(MLChannel *)channel {
    [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Permission denied", nil)];
}

- (void) serverModelInvalidChannelNameError:(MLServerModel *)model {
    [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Invalid channel name", nil)];
}

- (void) serverModelModifySuperUserError:(MLServerModel *)model {
    [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Cannot modify SuperUser", nil)];
}

- (void) serverModelTextMessageTooLongError:(MLServerModel *)model {
    [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Message too long", nil)];
}

- (void) serverModelTemporaryChannelError:(MLServerModel *)model {
    [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Not permitted in temporary channel", nil)];
}

- (void) serverModel:(MLServerModel *)model missingCertificateErrorForUser:(MLUser *)user {
    if (user == nil) {
        [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Missing certificate", nil)];
    } else {
        [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Missing certificate for user", nil)];
    }
}

- (void) serverModel:(MLServerModel *)model invalidUsernameErrorForName:(NSString *)name {
    if (name == nil) {
        [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Invalid username", nil)];
    } else {
        [[MUNotificationController sharedController] addNotification:[NSString stringWithFormat:NSLocalizedString(@"Invalid username: %@", nil), name]];
    }
}

- (void) serverModelChannelFullError:(MLServerModel *)model {
    [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Channel is full", nil)];
}

- (void) serverModel:(MLServerModel *)model permissionDeniedForReason:(NSString *)reason {
    if (reason == nil) {
        [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Permission denied", nil)];
    } else {
        [[MUNotificationController sharedController] addNotification:[NSString stringWithFormat:
                                                                        NSLocalizedString(@"Permission denied: %@",
                                                                                          @"Permission denied with reason"),
                                                                        reason]];
    }
}

- (void) serverModel:(MLServerModel *)model textMessageReceived:(MLTextMessage *)msg fromUser:(MLUser *)user {
    if (_segmentedControl.selectedSegmentIndex != 1) { // When not in messages view
        _unreadMessages++;
        [self updateUnreadMessageCount];
    }
}

- (void)updateUnreadMessageCount {
    NSString *title = NSLocalizedString(@"Messages", nil);
    if (_unreadMessages) {
        NSString *count = _unreadMessages > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)_unreadMessages];
        title = [NSString stringWithFormat:@"%@ (%@)", title, count];
    }
    [_segmentedControl setTitle:title forSegmentAtIndex:1];
}

#pragma mark - Actions

- (NSArray<UIMenuElement *> *)serverMenuActions {
    MLUser *connUser = [_model connectedUser];
    BOOL inMessagesView = self.viewControllers.firstObject == _messagesView;
    __weak MUServerRootViewController *weakSelf = self;
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    NSArray<NSString *> *methods = @[@"vad", @"ptt", @"continuous"];
    NSArray<NSString *> *titles = @[NSLocalizedString(@"Voice Activated", nil), NSLocalizedString(@"Push-to-talk", nil), NSLocalizedString(@"Continuous", nil)];
    NSArray<NSString *> *symbols = @[@"waveform", @"hand.tap", @"mic.fill"];
    NSMutableArray<UIAction *> *modeActions = [NSMutableArray array];
    NSString *current = [NSUserDefaults.standardUserDefaults stringForKey:@"AudioTransmitMethod"] ?: @"vad";
    for (NSUInteger index = 0; index < methods.count; index++) {
        NSString *method = methods[index];
        UIAction *mode = [UIAction actionWithTitle:titles[index] image:[UIImage systemImageNamed:symbols[index]] identifier:method handler:^(UIAction *action) {
            [(MUApplicationDelegate *)UIApplication.sharedApplication.delegate setAudioTransmitMethod:method];
        }];
        mode.state = [method isEqualToString:current] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [modeActions addObject:mode];
    }
    [actions addObject:[UIMenu menuWithTitle:NSLocalizedString(@"Transmission", nil) image:[UIImage systemImageNamed:@"mic"] identifier:nil options:UIMenuOptionsSingleSelection children:modeActions]];
    UIAction *disconnect = [UIAction actionWithTitle:NSLocalizedString(@"Disconnect", nil) image:[UIImage systemImageNamed:@"xmark.circle"] identifier:nil handler:^(UIAction *action) {
        [[MUConnectionController sharedController] disconnectFromServer];
    }];
    disconnect.attributes = UIMenuElementAttributesDestructive;
    [actions addObject:disconnect];
    
    [actions addObject:[UIAction actionWithTitle:NSLocalizedString(@"Access Tokens", nil) image:[UIImage systemImageNamed:@"key"] identifier:nil handler:^(UIAction *action) {
        MUServerRootViewController *controller = weakSelf;
        if (!controller) return;
        MUAccessTokenViewController *tokenViewController = [[MUAccessTokenViewController alloc] initWithServerModel:controller->_model];
        UINavigationController *navCtrl = [[UINavigationController alloc] initWithRootViewController:tokenViewController];
        [controller presentViewController:navCtrl animated:YES completion:nil];
    }]];
    
    if (!inMessagesView) {
        [actions addObject:[UIAction actionWithTitle:NSLocalizedString(@"Certificates", nil) image:[UIImage systemImageNamed:@"checkmark.seal"] identifier:nil handler:^(UIAction *action) {
            MUServerRootViewController *controller = weakSelf;
            if (!controller) return;
            MUCertificateViewController *certView = [[MUCertificateViewController alloc] initWithCertificates:[controller->_model serverCertificates]];
            UINavigationController *navCtrl = [[UINavigationController alloc] initWithRootViewController:certView];
            UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                        target:controller
                                                                                        action:@selector(childDoneButton:)];
            certView.navigationItem.leftBarButtonItem = doneButton;
            [controller presentViewController:navCtrl animated:YES completion:nil];
        }]];
    }
    
    if (connUser && !connUser.isAuthenticated) {
        [actions addObject:[UIAction actionWithTitle:NSLocalizedString(@"Self-Register", nil) image:[UIImage systemImageNamed:@"person.crop.circle.badge.checkmark"] identifier:nil handler:^(UIAction *action) {
            MUServerRootViewController *controller = weakSelf;
            if (!controller) return;
            NSString *title = NSLocalizedString(@"User Registration", nil);
            NSString *msg = [NSString stringWithFormat:
                             NSLocalizedString(@"You are about to register yourself on this server. "
                                               @"This cannot be undone, and your username cannot be changed once this is done. "
                                               @"You will forever be known as '%@' on this server.\n\n"
                                               @"Are you sure you want to register yourself?",
                                               @"Self-registration with given username"),
                             [connUser userName]];
            UIAlertController *alertCtrl = [UIAlertController alertControllerWithTitle:title
                                                                               message:msg
                                                                        preferredStyle:UIAlertControllerStyleAlert];
            [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"No", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil]];
            [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", nil)
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction * _Nonnull action) {
                [controller->_model registerConnectedUser];
            }]];
            
            [controller presentViewController:alertCtrl animated:YES completion:nil];
        }]];
    }
    
    if (inMessagesView) {
        [actions addObject:[UIAction actionWithTitle:NSLocalizedString(@"Clear Messages", nil) image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *action) {
            MUServerRootViewController *controller = weakSelf;
            if (controller) [controller->_messagesView clearAllMessages];
        }]];
    }
    return actions;
}

- (void) childDoneButton:(id)sender {
    [[self presentedViewController] dismissViewControllerAnimated:YES completion:nil];
}

@end
