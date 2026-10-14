// Copyright 2009-2010 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MUServerViewController.h"
#import "MUUserStateAcessoryView.h"
#import "MUNotificationController.h"
#import "MUImage.h"
#import "MUServerTableViewCell.h"
#import "MUApplicationDelegate.h"

#import "MLClient.h"

static UIFont *MUServerFont(UIFontTextStyle style, BOOL bold, UITraitCollection *traits) {
    UIFont *font = [UIFont preferredFontForTextStyle:style compatibleWithTraitCollection:traits];
    return bold ? [UIFont fontWithDescriptor:[font.fontDescriptor fontDescriptorWithSymbolicTraits:font.fontDescriptor.symbolicTraits | UIFontDescriptorTraitBold] size:0] : font;
}

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
    MLServerModel                    *_serverModel;
    NSMutableArray                   *_modelItems;
    NSMutableDictionary              *_userIndexMap;
    NSMutableDictionary              *_channelIndexMap;
    BOOL                             _pttState;
    UIButton                         *_talkButton;
    UIStackView                      *_muteControls;
    UIButton                         *_microphoneButton, *_speakerButton;
    UILabel                          *_microphoneLabel, *_speakerLabel;
    UIVisualEffectView               *_voiceDock;
    UILabel                         *_voiceStatusLabel;
    UIView                          *_channelHeader;
    UILabel                         *_serverNameLabel, *_channelTitleLabel, *_channelMetaLabel;
    NSInteger                       _maximumIndent;
    BOOL                            _modelRefreshScheduled;
}
- (NSInteger) indexForUser:(MLUser *)user;
- (void) reloadUser:(MLUser *)user;
- (void) rebuildModelArrayFromChannel:(MLChannel *)channel;
- (void) addChannelTreeToModel:(MLChannel *)channel indentLevel:(NSInteger)indentLevel;
- (void)scheduleModelRefresh;
- (void)configureCell:(MUServerTableViewCell *)cell item:(MUChannelNavigationItem *)item;
@end

@implementation MUServerViewController

#pragma mark -
#pragma mark Initialization and lifecycle

- (id) initWithServerModel:(MLServerModel *)serverModel {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _serverModel = serverModel;
        [_serverModel addDelegate:self];
    }
    return self;
}

- (void) dealloc {
    [_serverModel removeDelegate:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = UIColor.systemBackgroundColor;
    self.tableView.separatorColor = UIColor.separatorColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;
    self.tableView.selfSizingInvalidation = UITableViewSelfSizingInvalidationEnabledIncludingConstraints;
    _channelHeader = [UIView new];
    _serverNameLabel = [UILabel new];
    _channelTitleLabel = [UILabel new];
    _channelMetaLabel = [UILabel new];
    for (UILabel *label in @[_serverNameLabel, _channelTitleLabel, _channelMetaLabel]) {
        label.adjustsFontForContentSizeCategory = YES;
        [_channelHeader addSubview:label];
    }
    UIStackView *summary = [[UIStackView alloc] initWithArrangedSubviews:@[_serverNameLabel, _channelTitleLabel, _channelMetaLabel]];
    summary.axis = UILayoutConstraintAxisVertical; summary.spacing = 6; summary.translatesAutoresizingMaskIntoConstraints = NO;
    [_channelHeader addSubview:summary];
    for (UILabel *label in @[_serverNameLabel, _channelTitleLabel, _channelMetaLabel]) label.numberOfLines = 0;
    NSLayoutConstraint *summaryBottom = [summary.bottomAnchor constraintEqualToAnchor:_channelHeader.bottomAnchor constant:-16];
    // UITableView may temporarily impose a zero header height during updates.
    // Its encapsulated size takes precedence until the header is measured.
    summaryBottom.priority = UILayoutPriorityRequired - 1;
    [NSLayoutConstraint activateConstraints:@[
        [summary.leadingAnchor constraintEqualToAnchor:_channelHeader.leadingAnchor constant:20], [summary.trailingAnchor constraintEqualToAnchor:_channelHeader.trailingAnchor constant:-20],
        [summary.topAnchor constraintEqualToAnchor:_channelHeader.topAnchor constant:16], summaryBottom
    ]];
    [self updateChannelSummary];
    [self resizeChannelHeader];
    [self registerForTraitChanges:@[[UITraitPreferredContentSizeCategory class]] withHandler:^(__kindof MUServerViewController *controller, UITraitCollection *previousTraits) {
        [controller updateChannelSummary];
        [controller.tableView reloadData];
        if (controller.view.window) { [controller removeVoiceDock]; [controller installVoiceDock]; }
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _modelRefreshScheduled = NO;
    [self rebuildModelArrayFromChannel:_serverModel.rootChannel];
    [self.tableView reloadData];
    [self updateChannelSummary];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self installVoiceDock];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioSettingsUpdated:) name:MLAudioDidRestartNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioSettingsUpdated:) name:MUAudioTransmissionModeDidChangeNotification object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self resizeChannelHeader];
    CGFloat bottom = _voiceDock ? ceil(_voiceDock.bounds.size.height) + 24 : 0;
    if (self.tableView.contentInset.bottom != bottom) {
        UIEdgeInsets insets = self.tableView.contentInset;
        insets.bottom = bottom;
        self.tableView.contentInset = insets;
        self.tableView.verticalScrollIndicatorInsets = UIEdgeInsetsMake(0, 0, bottom, 0);
    }
}

- (void)resizeChannelHeader {
    CGFloat width = self.tableView.bounds.size.width;
    if (width < 1) return;
    // Measure native labels independently of UITableView's current header
    // height; an encapsulated height of zero must not become the fitting result.
    CGFloat height = 32 + 12; // Vertical margins and two stack spacings.
    for (UILabel *label in @[_serverNameLabel, _channelTitleLabel, _channelMetaLabel])
        height += ceil([label sizeThatFits:CGSizeMake(MAX(1, width - 40), CGFLOAT_MAX)].height);
    CGRect frame = CGRectMake(0, 0, width, height);
    BOOL changed = !CGRectEqualToRect(_channelHeader.frame, frame);
    if (changed) _channelHeader.frame = frame;
    if (changed || self.tableView.tableHeaderView != _channelHeader)
        self.tableView.tableHeaderView = _channelHeader;
}

- (void)updateChannelSummary {
    if (!self.isViewLoaded) return;
    MLChannel *channel = _serverModel.connectedUser.channel ?: _serverModel.rootChannel;
    _serverNameLabel.text = _serverModel.hostname.length ? _serverModel.hostname : NSLocalizedString(@"Current Channel", nil);
    _serverNameLabel.font = MUServerFont(UIFontTextStyleCaption1, NO, self.traitCollection);
    _serverNameLabel.textColor = UIColor.secondaryLabelColor;
    _channelTitleLabel.text = channel.channelName;
    _channelTitleLabel.font = MUServerFont(UIFontTextStyleTitle2, YES, self.traitCollection);
    _channelTitleLabel.textColor = UIColor.labelColor;
    NSString *members = channel.users.count == 1 ? NSLocalizedString(@"1 member", nil) : [NSString stringWithFormat:NSLocalizedString(@"%lu members", nil), (unsigned long)channel.users.count];
    _channelMetaLabel.text = [NSString stringWithFormat:@"%@ · %@", members, [self transmissionModeTitle]];
    _channelMetaLabel.font = MUServerFont(UIFontTextStyleSubheadline, NO, self.traitCollection);
    _channelMetaLabel.textColor = UIColor.secondaryLabelColor;
    [self.view setNeedsLayout];
}

- (NSString *)transmissionModeTitle {
    switch (MLAudio.sharedAudio.transmitType) {
        case MLTransmitTypeToggle: return NSLocalizedString(@"Push-to-talk", nil);
        case MLTransmitTypeContinuous: return NSLocalizedString(@"Continuous", nil);
        default: return NSLocalizedString(@"Voice Activated", nil);
    }
}

- (void)installVoiceDock {
    if (_voiceDock || !self.view.window) return;
    UIVisualEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    BOOL supportsGlass = NO;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        UIGlassContainerEffect *glass = [UIGlassContainerEffect new];
        glass.spacing = 12;
        effect = glass;
        supportsGlass = YES;
    }
#endif
    _voiceDock = [[UIVisualEffectView alloc] initWithEffect:effect];
    _voiceDock.translatesAutoresizingMaskIntoConstraints = NO;
    if (!supportsGlass) {
        _voiceDock.layer.cornerRadius = 24;
        _voiceDock.clipsToBounds = YES;
    }
    _voiceDock.traitOverrides.preferredContentSizeCategory = self.traitCollection.preferredContentSizeCategory;
    BOOL pushToTalk = MLAudio.sharedAudio.transmitType == MLTransmitTypeToggle;
    _voiceStatusLabel = [UILabel new];
    _voiceStatusLabel.font = MUServerFont(UIFontTextStyleFootnote, YES, self.traitCollection);
    _voiceStatusLabel.textAlignment = NSTextAlignmentCenter;
    _voiceStatusLabel.adjustsFontForContentSizeCategory = YES;
    _voiceStatusLabel.numberOfLines = 0;
    _voiceStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    UIVisualEffect *statusEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *statusBadge = [[UIVisualEffectView alloc] initWithEffect:statusEffect];
    statusBadge.translatesAutoresizingMaskIntoConstraints = NO;
    statusBadge.layer.cornerRadius = 18;
    statusBadge.layer.cornerCurve = kCACornerCurveContinuous;
    statusBadge.clipsToBounds = YES;
    [statusBadge.contentView addSubview:_voiceStatusLabel];
    // Give the status its own material: scroll-edge fading alone leaves the
    // upper label overlapping readable channel rows on dense servers.
    UIView *statusRow = [UIView new];
    [statusRow addSubview:statusBadge];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[statusRow]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = pushToTalk ? UIStackViewAlignmentFill : UIStackViewAlignmentCenter;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_voiceDock.contentView addSubview:stack];
    if (pushToTalk) {
        _talkButton = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *configuration;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
        if (@available(iOS 26.0, *)) configuration = [UIButtonConfiguration glassButtonConfiguration];
        else
#endif
            configuration = [UIButtonConfiguration grayButtonConfiguration];
        configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        configuration.image = [MUImage symbolNamed:@"mic.fill" pointSize:27];
        configuration.title = NSLocalizedString(@"Hold to speak", nil);
        configuration.imagePadding = 10;
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(16, 20, 16, 20);
        configuration.titleLineBreakMode = NSLineBreakByWordWrapping;
        UIFont *titleFont = MUServerFont(UIFontTextStyleHeadline, NO, self.traitCollection);
        configuration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attributes) {
            NSMutableDictionary *updated = [attributes mutableCopy];
            updated[NSFontAttributeName] = titleFont;
            return updated;
        };
        configuration.baseForegroundColor = UIColor.labelColor;
        _talkButton.configuration = configuration;
        _talkButton.accessibilityLabel = NSLocalizedString(@"Push to Talk", nil);
        _talkButton.accessibilityHint = NSLocalizedString(@"Hold to speak", nil);
        __weak MUServerViewController *weakSelf = self;
        _talkButton.configurationUpdateHandler = ^(UIButton *button) {
            MUServerViewController *controller = weakSelf;
            BOOL active = button.highlighted || (controller && controller->_pttState);
            UIButtonConfiguration *updated = button.configuration;
            MLUser *user = controller ? controller->_serverModel.connectedUser : nil;
            BOOL muted = user.isSelfMuted || user.isMuted || user.isSuppressed;
            updated.baseForegroundColor = active ? UIColor.systemGreenColor : muted ? UIColor.systemRedColor : UIColor.labelColor;
            button.configuration = updated;
        };
        [_talkButton setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        _speakerButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _speakerButton.configuration = [self muteButtonConfigurationWithSymbol:@"speaker.wave.2.fill" muted:NO];
        [_speakerButton addTarget:self action:@selector(toggleSpeaker:) forControlEvents:UIControlEventTouchUpInside];
        _muteControls = [[UIStackView alloc] initWithArrangedSubviews:@[_talkButton, _speakerButton]];
        _muteControls.alignment = UIStackViewAlignmentCenter;
        _muteControls.spacing = 12;
        [stack addArrangedSubview:_muteControls];
        [NSLayoutConstraint activateConstraints:@[
            [_talkButton.heightAnchor constraintGreaterThanOrEqualToConstant:64],
            [_speakerButton.widthAnchor constraintEqualToConstant:64],
            [_speakerButton.heightAnchor constraintEqualToConstant:64]
        ]];
        [_talkButton addTarget:self action:@selector(talkOn:) forControlEvents:UIControlEventTouchDown];
        [_talkButton addTarget:self action:@selector(talkOff:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    } else {
        _microphoneButton = [self floatingMuteButtonWithSymbol:@"mic.fill" action:@selector(toggleMicrophone:)];
        _speakerButton = [self floatingMuteButtonWithSymbol:@"speaker.wave.2.fill" action:@selector(toggleSpeaker:)];
        _microphoneLabel = [self muteControlLabelWithTitle:NSLocalizedString(@"Mic", nil)];
        _speakerLabel = [self muteControlLabelWithTitle:NSLocalizedString(@"Audio", nil)];
        _muteControls = [[UIStackView alloc] initWithArrangedSubviews:@[
            [self muteControlWithButton:_microphoneButton label:_microphoneLabel],
            [self muteControlWithButton:_speakerButton label:_speakerLabel]
        ]];
        _muteControls.alignment = UIStackViewAlignmentTop;
        _muteControls.spacing = 8;
        [stack addArrangedSubview:_muteControls];
    }
    UIWindow *window = self.view.window;
    [window addSubview:_voiceDock];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        // Include both the glass controls and their external text labels in the
        // system's scroll-edge treatment, so dense rows fade behind the dock.
        UIScrollEdgeElementContainerInteraction *edge = [UIScrollEdgeElementContainerInteraction new];
        edge.scrollView = self.tableView;
        edge.edge = UIRectEdgeBottom;
        [_voiceDock addInteraction:edge];
        self.tableView.bottomEdgeEffect.style = UIScrollEdgeEffectStyle.softStyle;
    }
#endif
    if (pushToTalk) {
        [NSLayoutConstraint activateConstraints:@[
            [_voiceDock.leadingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.leadingAnchor constant:16],
            [_voiceDock.trailingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.trailingAnchor constant:-16]
        ]];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_voiceDock.centerXAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.centerXAnchor],
        // Anchor the actual button. The labels below the mute buttons must
        // not move those buttons up relative to the push-to-talk controls.
        [_speakerButton.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor constant:-MAX(22, ceil(MUServerFont(UIFontTextStyleCaption2, NO, self.traitCollection).lineHeight) + 9)],
        [stack.leadingAnchor constraintEqualToAnchor:_voiceDock.contentView.leadingAnchor constant:10],
        [stack.trailingAnchor constraintEqualToAnchor:_voiceDock.contentView.trailingAnchor constant:-10],
        [stack.topAnchor constraintEqualToAnchor:_voiceDock.contentView.topAnchor constant:10],
        [stack.bottomAnchor constraintEqualToAnchor:_voiceDock.contentView.bottomAnchor constant:-10],
        [statusRow.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [statusBadge.centerXAnchor constraintEqualToAnchor:statusRow.centerXAnchor],
        [statusBadge.leadingAnchor constraintGreaterThanOrEqualToAnchor:statusRow.leadingAnchor],
        [statusBadge.trailingAnchor constraintLessThanOrEqualToAnchor:statusRow.trailingAnchor],
        [statusBadge.topAnchor constraintEqualToAnchor:statusRow.topAnchor],
        [statusBadge.bottomAnchor constraintEqualToAnchor:statusRow.bottomAnchor],
        [_voiceStatusLabel.leadingAnchor constraintEqualToAnchor:statusBadge.contentView.leadingAnchor constant:14],
        [_voiceStatusLabel.trailingAnchor constraintEqualToAnchor:statusBadge.contentView.trailingAnchor constant:-14],
        [_voiceStatusLabel.topAnchor constraintEqualToAnchor:statusBadge.contentView.topAnchor constant:7],
        [_voiceStatusLabel.bottomAnchor constraintEqualToAnchor:statusBadge.contentView.bottomAnchor constant:-7]
    ]];
    [self updateMuteControls];
    [self.view setNeedsLayout];
}

- (void)removeVoiceDock {
    if (_talkButton) [self talkOff:_talkButton];
    [_voiceDock removeFromSuperview];
    _voiceDock = nil; _muteControls = nil; _talkButton = nil;
    _microphoneButton = nil; _speakerButton = nil; _voiceStatusLabel = nil;
    _microphoneLabel = nil; _speakerLabel = nil;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _modelRefreshScheduled = NO;
    [self removeVoiceDock];
    UIEdgeInsets insets = self.tableView.contentInset; insets.bottom = 0;
    self.tableView.contentInset = insets;
    self.tableView.verticalScrollIndicatorInsets = UIEdgeInsetsZero;
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)audioSettingsUpdated:(NSNotification *)notification {
    if (!self.view.window) return;
    [self removeVoiceDock];
    [self installVoiceDock];
    [self updateChannelSummary];
}

- (UIButton *)floatingMuteButtonWithSymbol:(NSString *)symbol action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.configuration = [self muteButtonConfigurationWithSymbol:symbol muted:NO];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    UIFont *font = MUServerFont(UIFontTextStyleCaption2, NO, self.traitCollection);
    CGFloat width = MAX(96, ceil(MAX([NSLocalizedString(@"Mic", nil) sizeWithAttributes:@{NSFontAttributeName:font}].width, [NSLocalizedString(@"Audio", nil) sizeWithAttributes:@{NSFontAttributeName:font}].width)) + 24);
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:MIN(width, (self.view.window.bounds.size.width - 40) / 2)],
        [button.heightAnchor constraintEqualToConstant:64]
    ]];
    return button;
}

- (UILabel *)muteControlLabelWithTitle:(NSString *)title {
    UILabel *label = [UILabel new];
    label.text = title;
    label.font = MUServerFont(UIFontTextStyleCaption2, YES, self.traitCollection);
    label.adjustsFontForContentSizeCategory = YES;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.accessibilityElementsHidden = YES;
    label.isAccessibilityElement = NO;
    return label;
}

- (UIStackView *)muteControlWithButton:(UIButton *)button label:(UILabel *)label {
    UIStackView *control = [[UIStackView alloc] initWithArrangedSubviews:@[button, label]];
    control.axis = UILayoutConstraintAxisVertical;
    control.alignment = UIStackViewAlignmentCenter;
    control.spacing = 6;
    [label.widthAnchor constraintEqualToAnchor:button.widthAnchor].active = YES;
    return control;
}

- (UIButtonConfiguration *)muteButtonConfigurationWithSymbol:(NSString *)symbol muted:(BOOL)muted {
    UIButtonConfiguration *configuration;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) configuration = muted ? [UIButtonConfiguration prominentGlassButtonConfiguration] : [UIButtonConfiguration glassButtonConfiguration];
    else
#endif
        configuration = muted ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration grayButtonConfiguration];
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    configuration.baseBackgroundColor = muted ? [UIColor systemRedColor] : nil;
    configuration.baseForegroundColor = muted ? [UIColor whiteColor] : [UIColor labelColor];
    configuration.image = [MUImage symbolNamed:symbol pointSize:28];
    configuration.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightMedium];
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(10, 12, 10, 12);
    return configuration;
}

- (void)updateMuteControls {
    if (!_muteControls) return;
    MLUser *user = _serverModel.connectedUser;
    BOOL microphoneMuted = user.isSelfMuted || user.isMuted || user.isSuppressed;
    BOOL speakerMuted = user.isSelfDeafened || user.isDeafened;
    _microphoneButton.enabled = user && !user.isMuted && !user.isSuppressed;
    _speakerButton.enabled = user && !user.isDeafened;
    _microphoneButton.selected = microphoneMuted;
    _speakerButton.selected = speakerMuted;
    _microphoneButton.configuration = [self muteButtonConfigurationWithSymbol:microphoneMuted ? @"mic.slash.fill" : @"mic.fill" muted:microphoneMuted];
    _speakerButton.configuration = [self muteButtonConfigurationWithSymbol:speakerMuted ? @"speaker.slash.fill" : @"speaker.wave.2.fill" muted:speakerMuted];
    _microphoneLabel.textColor = microphoneMuted ? UIColor.systemRedColor : UIColor.labelColor;
    _speakerLabel.textColor = speakerMuted ? UIColor.systemRedColor : UIColor.labelColor;
    _microphoneButton.accessibilityLabel = microphoneMuted ? NSLocalizedString(@"Unmute Microphone", nil) : NSLocalizedString(@"Mute Microphone", nil);
    _speakerButton.accessibilityLabel = speakerMuted ? NSLocalizedString(@"Unmute Speaker", nil) : NSLocalizedString(@"Mute Speaker", nil);
    _microphoneButton.accessibilityValue = microphoneMuted ? NSLocalizedString(@"Muted", nil) : NSLocalizedString(@"On", nil);
    _speakerButton.accessibilityValue = speakerMuted ? NSLocalizedString(@"Muted", nil) : NSLocalizedString(@"On", nil);
    _talkButton.enabled = user && !microphoneMuted && !speakerMuted;
    if (!_talkButton.enabled && _pttState) [self talkOff:_talkButton];
    [_talkButton setNeedsUpdateConfiguration];
    MLTalkState state = [self talkStateForUser:user];
    _voiceStatusLabel.text = speakerMuted ? NSLocalizedString(@"Audio off", nil) : microphoneMuted ? NSLocalizedString(@"Microphone muted", nil) : state != MLTalkStatePassive ? NSLocalizedString(@"Speaking", nil) : [self transmissionModeTitle];
    _voiceStatusLabel.textColor = speakerMuted || microphoneMuted ? UIColor.systemRedColor : state != MLTalkStatePassive ? UIColor.systemGreenColor : UIColor.labelColor;
}

- (void)toggleMicrophone:(UIButton *)button {
    MLUser *user = _serverModel.connectedUser;
    if (!user || user.isMuted || user.isSuppressed) return;
    BOOL mute = !user.isSelfMuted;
    [_serverModel setSelfMuted:mute andSelfDeafened:mute && user.isSelfDeafened];
}

- (void)toggleSpeaker:(UIButton *)button {
    MLUser *user = _serverModel.connectedUser;
    if (!user || user.isDeafened) return;
    if (user.isSelfDeafened) {
        [_serverModel setSelfMuted:NO andSelfDeafened:NO];
    } else {
        [_serverModel setSelfMuted:user.isSelfMuted andSelfDeafened:YES];
    }
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
    if (user == _serverModel.connectedUser) [self updateMuteControls];
    if (!self.isViewLoaded || !self.view.window) return;
    NSInteger userIndex = [self indexForUser:user];
    if (userIndex != NSNotFound) {
        MUServerTableViewCell *cell = (id)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:userIndex inSection:0]];
        if (cell) [self configureCell:cell item:_modelItems[userIndex]];
    }
}

- (void)scheduleModelRefresh {
    // Initial protocol events arrive before this controller is presented and
    // may change several tree rows at once. Do not create a table for them or
    // infer insert/delete counts from individual callbacks.
    if (!self.isViewLoaded || !self.view.window || _modelRefreshScheduled) return;
    _modelRefreshScheduled = YES;
    __weak MUServerViewController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        MUServerViewController *controller = weakSelf;
        if (!controller || !controller->_modelRefreshScheduled) return;
        controller->_modelRefreshScheduled = NO;
        if (!controller.isViewLoaded || !controller.view.window) return;
        [controller rebuildModelArrayFromChannel:controller->_serverModel.rootChannel];
        [controller.tableView reloadData];
        [controller updateMuteControls];
    });
}

- (void) rebuildModelArrayFromChannel:(MLChannel *)channel {
    _maximumIndent = 0;
    _modelItems = [[NSMutableArray alloc] init];

    _userIndexMap = [[NSMutableDictionary alloc] init];

    _channelIndexMap = [[NSMutableDictionary alloc] init];

    [self addChannelTreeToModel:channel indentLevel:0];
    [self updateChannelSummary];
}



- (void) addChannelTreeToModel:(MLChannel *)channel indentLevel:(NSInteger)indentLevel {
    _maximumIndent = MAX(_maximumIndent, indentLevel + (channel.users.count ? 1 : 0));
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

- (UIView *)channelAccessory:(MLChannel *)channel current:(BOOL)current {
    UILabel *count = [UILabel new];
    count.font = MUServerFont(UIFontTextStyleCaption1, NO, self.traitCollection);
    count.textColor = UIColor.secondaryLabelColor;
    count.text = [NSString stringWithFormat:@"%lu", (unsigned long)channel.users.count];
    NSMutableArray *views = [NSMutableArray array];
    if (current) {
        UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
        check.tintColor = UIColor.labelColor;
        check.contentMode = UIViewContentModeScaleAspectFit;
        [NSLayoutConstraint activateConstraints:@[[check.widthAnchor constraintEqualToConstant:18], [check.heightAnchor constraintEqualToConstant:18]]];
        [views addObject:check];
    }
    [views addObject:count];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.spacing = 8;
    stack.alignment = UIStackViewAlignmentCenter;
    CGSize textSize = [count sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    CGSize size = CGSizeMake(ceil(textSize.width) + (current ? 26 : 0), MAX(ceil(textSize.height), current ? 18 : 0));
    stack.frame = (CGRect){CGPointZero, size};
    stack.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    // UITableView briefly reuses the old accessory size while changing rows.
    // Keep that encapsulated size off the stack's fixed-size checkmark.
    UIView *accessory = [[UIView alloc] initWithFrame:stack.frame];
    [accessory addSubview:stack];
    accessory.accessibilityElementsHidden = YES;
    return accessory;
}

- (MLTalkState)talkStateForUser:(MLUser *)user {
    if (user == _serverModel.connectedUser && MLAudio.sharedAudio.transmitType == MLTransmitTypeToggle)
        return MLAudio.sharedAudio.forceTransmit ? MLTalkStateTalking : MLTalkStatePassive;
    return user.talkState;
}

- (NSString *)statusForUser:(MLUser *)user {
    if (user.isSelfDeafened || user.isDeafened) return NSLocalizedString(@"Audio off", nil);
    if (user.isMuted || user.isSuppressed) return NSLocalizedString(@"Muted by server", nil);
    if (user.isSelfMuted) return NSLocalizedString(@"Microphone muted", nil);
    if (user.isLocalMuted) return NSLocalizedString(@"Locally muted", nil);
    switch ([self talkStateForUser:user]) {
        case MLTalkStateWhispering: return NSLocalizedString(@"Whispering", nil);
        case MLTalkStateShouting: return NSLocalizedString(@"Shouting", nil);
        case MLTalkStateTalking: return NSLocalizedString(@"Speaking", nil);
        default: return NSLocalizedString(@"Listening", nil);
    }
}

- (void)updateUserAppearance:(UITableViewCell *)cell user:(MLUser *)user {
    if (!cell) return;
    MLTalkState state = [self talkStateForUser:user];
    UIListContentConfiguration *content = [(UIListContentConfiguration *)cell.contentConfiguration copy];
    content.image = [MUImage userTalkSymbolForState:state];
    content.imageProperties.tintColor = [MUImage userTalkColorForState:state];
    NSString *status = [self statusForUser:user];
    content.secondaryText = user == _serverModel.connectedUser ? [NSString stringWithFormat:@"%@ · %@", NSLocalizedString(@"You", nil), status] : status;
    content.secondaryTextProperties.color = state != MLTalkStatePassive ? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
    cell.contentConfiguration = content;
    NSMutableArray *values = [NSMutableArray arrayWithObject:content.secondaryText];
    if (user.isAuthenticated) [values addObject:NSLocalizedString(@"Authenticated", nil)];
    if (user.isPrioritySpeaker) [values addObject:NSLocalizedString(@"Priority speaker", nil)];
    cell.accessibilityValue = [values componentsJoinedByString:@", "];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MUServerTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ChannelNavigationCell"];
    if (!cell) cell = [[MUServerTableViewCell alloc] initWithReuseIdentifier:@"ChannelNavigationCell"];
    MUChannelNavigationItem *item = _modelItems[indexPath.row];
    [self configureCell:cell item:item];
    return cell;
}

- (void)configureCell:(MUServerTableViewCell *)cell item:(MUChannelNavigationItem *)item {
    id object = item.object;
    BOOL channelRow = [object isKindOfClass:MLChannel.class];
    cell.channelRow = channelRow;
    CGFloat indent = MIN(14, MAX(4, (self.tableView.bounds.size.width - 220) / MAX(1, _maximumIndent)));
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.textProperties.font = MUServerFont(UIFontTextStyleBody, channelRow || object == _serverModel.connectedUser, self.traitCollection);
    content.textProperties.numberOfLines = 0;
    content.secondaryTextProperties.font = MUServerFont(UIFontTextStyleCaption1, NO, self.traitCollection);
    content.secondaryTextProperties.numberOfLines = 0;
    content.imageProperties.maximumSize = CGSizeMake(40, 24);
    content.imageProperties.reservedLayoutSize = CGSizeMake(40, 24);
    content.imageToTextPadding = 8;
    content.textToSecondaryTextVerticalPadding = 2;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(10, 16 + item.indentLevel * indent, 10, 16);
    cell.backgroundColor = channelRow ? UIColor.secondarySystemGroupedBackgroundColor : UIColor.systemBackgroundColor;
    if (channelRow) {
        MLChannel *channel = object;
        BOOL current = channel == _serverModel.connectedUser.channel;
        content.image = [MUImage channelSymbolForCurrentChannel:current];
        content.imageProperties.tintColor = UIColor.secondaryLabelColor;
        content.text = channel.channelName;
        cell.accessoryView = [self channelAccessory:channel current:current];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessibilityTraits = UIAccessibilityTraitButton;
        cell.accessibilityValue = [NSString stringWithFormat:@"%@%lu", current ? [NSLocalizedString(@"Current Channel", nil) stringByAppendingString:@", "] : @"", (unsigned long)channel.users.count];
    } else {
        MLUser *user = object;
        content.text = user.userName;
        cell.accessoryView = [MUUserStateAcessoryView viewForUser:user];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessibilityTraits = UIAccessibilityTraitStaticText;
    }
    cell.contentConfiguration = content;
    cell.accessibilityLabel = content.text;
    if (!channelRow) [self updateUserAppearance:cell user:object];
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

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return UITableViewAutomaticDimension; }

#pragma mark - MLServerModel delegate

- (void) serverModel:(MLServerModel *)model joinedServerAsUser:(MLUser *)user {
    [self scheduleModelRefresh];
}

- (void) serverModel:(MLServerModel *)model userJoined:(MLUser *)user {
    [self scheduleModelRefresh];
}

- (void) serverModel:(MLServerModel *)model userDisconnected:(MLUser *)user {
}

- (void) serverModel:(MLServerModel *)model userLeft:(MLUser *)user {
    [self scheduleModelRefresh];
}

- (void)serverModel:(MLServerModel *)model userTalkStateChanged:(MLUser *)user {
    if (!self.isViewLoaded || !self.view.window) return;
    if (user == model.connectedUser) [self updateMuteControls];
    NSInteger row = [self indexForUser:user];
    if (row == NSNotFound) return;
    [self updateUserAppearance:[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]] user:user];
}

- (void) serverModel:(MLServerModel *)model channelAdded:(MLChannel *)channel {
    [self scheduleModelRefresh];
}

- (void) serverModel:(MLServerModel *)model channelRemoved:(MLChannel *)channel {
    [self scheduleModelRefresh];
}

- (void) serverModel:(MLServerModel *)model channelMoved:(MLChannel *)channel {
    [self scheduleModelRefresh];
}

- (void) serverModel:(MLServerModel *)model channelRenamed:(MLChannel *)channel {
    [self scheduleModelRefresh];
}

- (void)serverModel:(MLServerModel *)model channelPositionChanged:(MLChannel *)channel {
    [self scheduleModelRefresh];
}

- (void)serverModel:(MLServerModel *)model userRenamed:(MLUser *)user {
    [self scheduleModelRefresh];
}

- (void) serverModel:(MLServerModel *)model userMoved:(MLUser *)user toChannel:(MLChannel *)chan fromChannel:(MLChannel *)prevChan byUser:(MLUser *)mover {
    [self scheduleModelRefresh];
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

- (void) talkOn:(UIButton *)button {
    MLUser *user = _serverModel.connectedUser;
    if (!user || user.isSelfMuted || user.isMuted || user.isSuppressed || user.isSelfDeafened || user.isDeafened) return;
    _pttState = YES;
    [[MLAudio sharedAudio] setForceTransmit:YES];
    [button setNeedsUpdateConfiguration];
    [self reloadUser:_serverModel.connectedUser];
}

- (void) talkOff:(UIButton *)button {
    _pttState = NO;
    [[MLAudio sharedAudio] setForceTransmit:NO];
    [button setNeedsUpdateConfiguration];
    [self reloadUser:_serverModel.connectedUser];
}

#pragma mark - Background notification

- (void)appDidEnterBackground:(NSNotification *)notification {
    if (_talkButton) [self talkOff:_talkButton];
}

@end

