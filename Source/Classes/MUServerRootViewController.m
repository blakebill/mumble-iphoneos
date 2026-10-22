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


// Keep the message controller attached while the secondary display becomes a
// shared message/control surface. Folding never transfers a live conversation.
@interface MUServerSecondaryViewController : UIViewController
@property(nonatomic) BOOL showsVoiceControls;
@property(nonatomic) BOOL showsPaneTitle;
- (instancetype)initWithMessages:(MUMessagesViewController *)messages server:(MUServerViewController *)server;
@end

@implementation MUServerSecondaryViewController {
    MUMessagesViewController *_messages;
    __weak MUServerViewController *_server;
    UIView *_controlsView;
    UILabel *_paneTitleLabel;
    CGFloat _controlsHeight;
}
- (instancetype)initWithMessages:(MUMessagesViewController *)messages server:(MUServerViewController *)server {
    if ((self = [super init])) { _messages = messages; _server = server; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.clipsToBounds = YES;
    [self addChildViewController:_messages];
    [self.view addSubview:_messages.view];
    [_messages didMoveToParentViewController:self];
    _paneTitleLabel = [UILabel new];
    _paneTitleLabel.text = NSLocalizedString(@"Messages", nil);
    _paneTitleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    _paneTitleLabel.adjustsFontForContentSizeCategory = YES;
    _paneTitleLabel.numberOfLines = 0;
    [self.view addSubview:_paneTitleLabel];
    [self registerForTraitChanges:@[[UITraitPreferredContentSizeCategory class]] withHandler:^(__kindof MUServerSecondaryViewController *controller, UITraitCollection *previousTraits) {
        [controller.view setNeedsLayout];
    }];
    _controlsView = [UIView new];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    _controlsHeight = 220;
    [self.view addSubview:_controlsView];
    [self updateContent];
}
- (void)setShowsVoiceControls:(BOOL)showsVoiceControls {
    if (_showsVoiceControls == showsVoiceControls) return;
    _showsVoiceControls = showsVoiceControls;
    if (self.isViewLoaded) [self updateContent];
}
- (void)setShowsPaneTitle:(BOOL)showsPaneTitle {
    if (_showsPaneTitle == showsPaneTitle) return;
    _showsPaneTitle = showsPaneTitle;
    [self.viewIfLoaded setNeedsLayout];
}
- (void)updateContent {
    _controlsView.hidden = !_showsVoiceControls;
    _server.voiceControlsHostView = _showsVoiceControls ? _controlsView : nil;
    [self.view setNeedsLayout];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect content = self.view.bounds;
    CGRect safe = self.view.safeAreaLayoutGuide.layoutFrame;
    _paneTitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2 compatibleWithTraitCollection:self.traitCollection];
    _paneTitleLabel.hidden = !_showsPaneTitle || CGRectIsEmpty(content);
    CGFloat heading = _showsPaneTitle ? ceil([_paneTitleLabel sizeThatFits:CGSizeMake(MAX(1, safe.size.width - 40), CGFLOAT_MAX)].height) : 0;
    _paneTitleLabel.frame = CGRectMake(CGRectGetMinX(safe) + 20, CGRectGetMinY(safe) + 16, MAX(0, safe.size.width - 40), heading);
    CGFloat messageTop = _showsPaneTitle ? MIN(content.size.height, CGRectGetMaxY(_paneTitleLabel.frame) + 12) : 0;
    CGFloat footer = _showsVoiceControls ? MIN(_controlsHeight, content.size.height) : 0;
    _messages.view.frame = CGRectMake(0, messageTop, content.size.width, MAX(0, content.size.height - messageTop - footer));
    _controlsView.frame = _showsVoiceControls ? CGRectMake(0, content.size.height - footer, content.size.width, footer) : CGRectZero;
    [_server layoutVoiceControls];
    if (_showsVoiceControls) {
        CGFloat height = [_server voiceControlsContentHeight];
        if (height > 0) {
            CGFloat preferred = ceil(height + 24 + _controlsView.safeAreaInsets.top + _controlsView.safeAreaInsets.bottom);
            if (fabs(preferred - _controlsHeight) > .5) {
                _controlsHeight = preferred;
                [self.view setNeedsLayout];
            }
        }
    }
}
@end

@interface MUServerRootViewController () <MLConnectionDelegate, MLServerModelDelegate> {
    MLConnection                *_connection;
    MLServerModel               *_model;
    
    NSInteger                   _segmentIndex;
    UISegmentedControl          *_segmentedControl;
    UIBarButtonItem             *_menuButton;
    UIDeferredMenuElement       *_menuActions;
    UIBarButtonItem             *_disconnectButton;

    MUServerViewController      *_serverView;
    MUMessagesViewController    *_messagesView;
    
    NSInteger                   _unreadMessages;
    UIViewController            *_conversationContainer;
    MUServerSecondaryViewController *_secondaryView;
    BOOL                         _showingBothPanes, _usingFoldedControls, _usingBookLayout, _updatingLayout;
    CGRect                       _keyboardFrameInScreen;
    BOOL                         _hasKeyboardFrame;

}
- (NSArray<UIMenuElement *> *)serverMenuActions;
- (void)updateConversationLayout;
- (void)updateNativeArrangement;
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
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_model removeDelegate:self];
    [_connection setDelegate:nil];
}

- (void) takeOwnershipOfConnectionDelegate {
    [_connection setDelegate:self];
}

#pragma mark - View lifecycle

- (void) viewDidLoad {
    [super viewDidLoad];
    self.view.keyboardLayoutGuide.followsUndockedKeyboard = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardFrameWillChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardFrameWillChange:) name:UIKeyboardWillShowNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardFrameWillChange:) name:UIKeyboardWillHideNotification object:nil];

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
    _menuActions = actions;
    _menuButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:[UIMenu menuWithChildren:@[actions]]];
    _menuButton.accessibilityLabel = NSLocalizedString(@"Server", nil);
    
    UIImageSymbolConfiguration *barIcon = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium];
    _disconnectButton = [self barButtonWithImage:[[UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:barIcon] imageWithTintColor:[UIColor systemRedColor] renderingMode:UIImageRenderingModeAlwaysOriginal] action:@selector(disconnectButtonClicked:)];
    _disconnectButton.accessibilityLabel = NSLocalizedString(@"Disconnect", nil);
    _disconnectButton.title = NSLocalizedString(@"Disconnect", nil);
    
    [_segmentedControl sizeToFit];
    CGRect segmentFrame = _segmentedControl.frame;
    segmentFrame.size.width = MAX(segmentFrame.size.width, 200.0f);
    segmentFrame.size.height = 32.0f;
    _segmentedControl.frame = segmentFrame;
    [self updateUnreadMessageCount];

    
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
    if (@available(iOS 27.1, *)) {
        UIArrangementViewController *arrangement = [UIArrangementViewController new];
        _conversationContainer = arrangement;
        _secondaryView = [[MUServerSecondaryViewController alloc] initWithMessages:_messagesView server:_serverView];
        [self updateNativeArrangement];
        [arrangement setViewController:_serverView forPlacement:UIArrangementViewControllerViewPlacementPrimary animated:NO];
        [arrangement setViewController:_secondaryView forPlacement:UIArrangementViewControllerViewPlacementSecondary animated:NO];
        [self applyNavigationItemsToViewController:arrangement];
        [self setViewControllers:@[arrangement] animated:NO];
    } else
#endif
    {
        [self applyNavigationItemsToViewController:_serverView];
        [self setViewControllers:@[_serverView] animated:NO];
    }

    self.toolbar.barStyle = UIBarStyleDefault;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Presentation can finish without another layout pass. Reconcile after its
    // coordinator clears, using the final window geometry and division regions.
    __weak MUServerRootViewController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf updateConversationLayout];
        [weakSelf.viewIfLoaded setNeedsLayout];
    });
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self.view setNeedsLayout];
}

// Resolve layout from this scene's available space, including vertical system bars.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateConversationLayout];
}

static UIView *MUFirstResponderInView(UIView *view) {
    if (view.isFirstResponder) return view;
    for (UIView *child in view.subviews) {
        UIView *responder = MUFirstResponderInView(child);
        if (responder) return responder;
    }
    return nil;
}

- (void)keyboardFrameWillChange:(NSNotification *)notification {
    if (!self.viewIfLoaded.window || [notification.userInfo[UIKeyboardIsLocalUserInfoKey] isEqual:@NO]) return;
    _keyboardFrameInScreen = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    _hasKeyboardFrame = YES;
    [self.view setNeedsLayout];
}

- (void)updateConversationLayout {
    if (_updatingLayout || !self.view.window || self.viewControllers.count != 1 || self.transitionCoordinator) return;
    BOOL wide = NO, foldedControls = NO, bookLayout = NO;
    UIView *responder = MUFirstResponderInView(_messagesView.viewIfLoaded);
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
    if (@available(iOS 27.1, *)) {
        CGRect usable = self.view.safeAreaLayoutGuide.layoutFrame;
        CGFloat availableBottom = CGRectGetMaxY(usable);
        if (responder) {
            availableBottom = MIN(availableBottom, CGRectGetMinY(self.view.keyboardLayoutGuide.layoutFrame));
            // A keyboard on the lower display may not invalidate the navigation
            // container's guide. Resolve its system frame in this scene as well.
            if (_hasKeyboardFrame) {
                CGRect keyboard = [self.view convertRect:_keyboardFrameInScreen fromCoordinateSpace:self.view.window.windowScene.screen.coordinateSpace];
                if (!CGRectIsEmpty(CGRectIntersection(usable, keyboard)) && keyboard.size.width >= usable.size.width * .5)
                    availableBottom = MIN(availableBottom, CGRectGetMinY(keyboard));
            }
        }
        wide = usable.size.width >= 720 && availableBottom - CGRectGetMinY(usable) >= 280;
        for (UIViewReservedRegion *region in [self.view reservedRegionsOfKind:UIViewReservedRegionKind.divisionRegionKind]) {
            CGRect division = region.frame;
            if (CGRectIsEmpty(CGRectIntersection(usable, division))) continue;
            if (division.size.width > division.size.height) {
                // Tabletop: visible channels above, conversation and controls below.
                wide = NO;
                if (responder) _segmentedControl.selectedSegmentIndex = 1;
                foldedControls = _segmentedControl.selectedSegmentIndex == 0 && usable.size.width >= 360 &&
                    CGRectGetMinY(division) - CGRectGetMinY(usable) >= 260 &&
                    CGRectGetMaxY(usable) - CGRectGetMaxY(division) >= 260;
            } else {
                // Book: retain the same leading Server / trailing Messages hierarchy
                // as the unfolded split. Voice controls stay with their server pane.
                BOOL rtl = self.view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
                CGFloat leading = rtl ? CGRectGetMaxX(usable) - CGRectGetMaxX(division) : CGRectGetMinX(division) - CGRectGetMinX(usable);
                CGFloat trailing = rtl ? CGRectGetMinX(division) - CGRectGetMinX(usable) : CGRectGetMaxX(usable) - CGRectGetMaxX(division);
                bookLayout = leading >= 280 && trailing >= 320 && availableBottom - CGRectGetMinY(usable) >= 280;
                wide = bookLayout;
                if (!wide && responder) _segmentedControl.selectedSegmentIndex = 1;
            }
            break;
        }
    }
#endif
    if (wide == _showingBothPanes && foldedControls == _usingFoldedControls && bookLayout == _usingBookLayout &&
        _segmentIndex == _segmentedControl.selectedSegmentIndex) return;
    _updatingLayout = YES;
    [MLAudio.sharedAudio setForceTransmit:NO];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
    if (@available(iOS 27.1, *)) {
        _showingBothPanes = wide;
        _usingFoldedControls = foldedControls;
        _usingBookLayout = bookLayout;
        if (wide) {
            _conversationContainer.navigationItem.titleView = nil;
            _conversationContainer.navigationItem.title = nil;
        } else {
            if (responder) _segmentedControl.selectedSegmentIndex = 1;
            [self applyNavigationItemsToViewController:_conversationContainer];
        }
        if (wide || foldedControls || _segmentedControl.selectedSegmentIndex == 1) {
            _unreadMessages = 0;
            [self updateUnreadMessageCount];
            [MUApplicationDelegate setApplicationBadgeCount:0];
        }
        _segmentIndex = _segmentedControl.selectedSegmentIndex;
        [self updateNativeArrangement];
    }
#endif
    _updatingLayout = NO;
    if (responder) {
        __weak UIView *weakResponder = responder;
        dispatch_async(dispatch_get_main_queue(), ^{ if (weakResponder.window) [weakResponder becomeFirstResponder]; });
    }
}

// Both children keep their placement for the lifetime of the connection. Collapsing
// a placement through its native dimensions avoids a controller handoff during folds.
- (void)updateNativeArrangement {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
    if (@available(iOS 27.1, *)) {
        _secondaryView.showsVoiceControls = _usingFoldedControls;
        _secondaryView.showsPaneTitle = _showingBothPanes;
        _serverView.showsPaneTitle = _showingBothPanes;
        BOOL splitPanes = _showingBothPanes || _usingFoldedControls;
        UISplitArrangement *split = [UISplitArrangement splitArrangement];
        split.axes = _usingFoldedControls ? UIAxisVertical : UIAxisHorizontal;
        for (NSUInteger index = 0; index < 2; index++) {
            BOOL visible = splitPanes || _segmentedControl.selectedSegmentIndex == index;
            UISplitArrangementViewProperties *properties = [UISplitArrangementViewProperties new];
            properties.layoutPriority = visible ? 1 : 0;
            if (splitPanes) {
                properties.width.minimum = [UISplitArrangementDimension absoluteDimension:index == 0 ? 280 : 320];
                properties.height.minimum = [UISplitArrangementDimension absoluteDimension:240];
                if (index == 0) properties.width.preferred = [UISplitArrangementDimension fractionalDimension:.42];
            } else {
                UISplitArrangementDimension *zero = [UISplitArrangementDimension absoluteDimension:0];
                properties.width.minimum = zero;
                properties.height.minimum = zero;
                properties.width.preferred = visible ? [UISplitArrangementDimension fractionalDimension:1] : zero;
                properties.height.preferred = visible ? [UISplitArrangementDimension fractionalDimension:1] : zero;
                if (!visible) { properties.width.maximum = zero; properties.height.maximum = zero; }
            }
            [split setViewProperties:properties forPlacement:index == 0 ? UIArrangementViewControllerViewPlacementPrimary : UIArrangementViewControllerViewPlacementSecondary];
        }
        // A compact conversation above a horizontal fold still uses that axis.
        if (!splitPanes) split.axes = UIAxisHorizontal | UIAxisVertical;
        [(UIArrangementViewController *)_conversationContainer updateArrangement:split animated:NO];
    }
#endif
}

- (UIBarButtonItem *)barButtonWithImage:(UIImage *)image action:(SEL)action {
    return [[UIBarButtonItem alloc] initWithImage:image style:UIBarButtonItemStylePlain target:self action:action];
}

- (void) applyNavigationItemsToViewController:(UIViewController *)controller {
    controller.navigationItem.titleView = _segmentedControl;
    controller.navigationItem.leftBarButtonItem = _disconnectButton;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
    if (@available(iOS 27.1, *)) {
        controller.navigationItem.rightBarButtonItem = nil;
        controller.navigationItem.additionalOverflowItems = _menuActions;
    } else
#endif
    {
        controller.navigationItem.rightBarButtonItem = _menuButton;
    }
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
    if (_showingBothPanes) return;
    if (_segmentedControl.selectedSegmentIndex == 0) [_messagesView.viewIfLoaded endEditing:YES];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
    if (@available(iOS 27.1, *)) {
        [self updateConversationLayout];
    } else
#endif
    {
        UIViewController *selected = _segmentedControl.selectedSegmentIndex == 1 ? _messagesView : _serverView;
        [self applyNavigationItemsToViewController:selected];
        [self setViewControllers:@[selected] animated:NO];
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
    [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Permission denied", nil) fromViewController:self];
}

- (void) serverModelInvalidChannelNameError:(MLServerModel *)model {
    [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Invalid channel name", nil) fromViewController:self];
}

- (void) serverModelModifySuperUserError:(MLServerModel *)model {
    [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Cannot modify SuperUser", nil) fromViewController:self];
}

- (void) serverModelTextMessageTooLongError:(MLServerModel *)model {
    [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Message too long", nil) fromViewController:self];
}

- (void) serverModelTemporaryChannelError:(MLServerModel *)model {
    [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Not permitted in temporary channel", nil) fromViewController:self];
}

- (void) serverModel:(MLServerModel *)model missingCertificateErrorForUser:(MLUser *)user {
    if (user == nil) {
        [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Missing certificate", nil) fromViewController:self];
    } else {
        [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Missing certificate for user", nil) fromViewController:self];
    }
}

- (void) serverModel:(MLServerModel *)model invalidUsernameErrorForName:(NSString *)name {
    if (name == nil) {
        [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Invalid username", nil) fromViewController:self];
    } else {
        [[MUNotificationController sharedController] addNotification:[NSString stringWithFormat:NSLocalizedString(@"Invalid username: %@", nil), name] fromViewController:self];
    }
}

- (void) serverModelChannelFullError:(MLServerModel *)model {
    [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Channel is full", nil) fromViewController:self];
}

- (void) serverModel:(MLServerModel *)model permissionDeniedForReason:(NSString *)reason {
    if (reason == nil) {
        [[MUNotificationController sharedController] addNotification:NSLocalizedString(@"Permission denied", nil) fromViewController:self];
    } else {
        [[MUNotificationController sharedController] addNotification:[NSString stringWithFormat:
                                                                        NSLocalizedString(@"Permission denied: %@",
                                                                                          @"Permission denied with reason"),
                                                                        reason] fromViewController:self];
    }
}

- (void) serverModel:(MLServerModel *)model textMessageReceived:(MLTextMessage *)msg fromUser:(MLUser *)user {
    if (!_showingBothPanes && !_usingFoldedControls && _segmentedControl.selectedSegmentIndex != 1) { // When not in messages view
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
    BOOL inMessagesView = _showingBothPanes || _usingFoldedControls || _segmentedControl.selectedSegmentIndex == 1;
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
    
    if (_showingBothPanes || _usingFoldedControls || !inMessagesView) {
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
