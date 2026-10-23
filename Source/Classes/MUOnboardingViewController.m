#import "MUOnboardingViewController.h"
#import "MUApplicationDelegate.h"
#import "MUCertificateController.h"
#import "MUCertificateCreationView.h"
#import "MUCertificateDiskImportViewController.h"
#import "MUInterface.h"

NSString *const MUInitialSetupStartedKey = @"InitialSetupStarted";
NSString *const MUInitialSetupCompletedKey = @"InitialSetupCompleted";

@interface MUOnboardingViewController () {
    NSUInteger _step;
    void (^_completion)(void);
    UIStackView *_headerStack;
    UIStackView *_footerStack;
    UILabel *_certificateStatus;
    UIButton *_continueButton;
    BOOL _finished;
}
@property(nonatomic, strong, readwrite) UITableView *tableView;
- (instancetype)initWithStep:(NSUInteger)step completion:(void (^)(void))completion;
@end

@implementation MUOnboardingViewController

+ (BOOL)shouldPresentForDefaults:(NSUserDefaults *)defaults hasExistingInstallation:(BOOL)existing {
    if ([defaults boolForKey:MUInitialSetupCompletedKey]) return NO;
    // Upgrading an existing installation should not interrupt its home screen.
    // A partially completed first launch must still resume, even after the
    // launch has created its database.
    if (existing && ![defaults boolForKey:MUInitialSetupStartedKey]) {
        [defaults setBool:YES forKey:MUInitialSetupCompletedKey];
        return NO;
    }
    [defaults setBool:YES forKey:MUInitialSetupStartedKey];
    return YES;
}

- (instancetype)initWithCompletion:(void (^)(void))completion {
    return [self initWithStep:0 completion:completion];
}

- (instancetype)initWithStep:(NSUInteger)step completion:(void (^)(void))completion {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _step = step;
        _completion = [completion copy];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(certificatesChanged:) name:MUCertificatesDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (UILabel *)labelWithText:(NSString *)text style:(UIFontTextStyle)style {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.labelColor;
    return label;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    MUConfigureTable(self.tableView);
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.title = (@[NSLocalizedString(@"Welcome", nil), NSLocalizedString(@"Transmission", nil), NSLocalizedString(@"Certificate", nil)])[_step];
    self.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;

    UIImageView *symbol = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:_step == 0 ? @"waveform" : _step == 1 ? @"mic.fill" : @"person.crop.circle.badge.checkmark"]];
    symbol.contentMode = UIViewContentModeScaleAspectFit;
    symbol.tintColor = UIColor.tintColor;
    [symbol.heightAnchor constraintEqualToConstant:64].active = YES;
    symbol.isAccessibilityElement = NO;
    NSString *heading = (@[NSLocalizedString(@"Welcome to Mumble", nil), NSLocalizedString(@"Choose how to speak", nil), NSLocalizedString(@"Your certificate", nil)])[_step];
    UILabel *title = [self labelWithText:heading style:UIFontTextStyleTitle1];
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
    title.font = [UIFont fontWithDescriptor:[title.font.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold] size:0];
    NSString *detail = (@[NSLocalizedString(@"Set up your voice and identity in a few simple steps.", nil), NSLocalizedString(@"You can change this later in Settings or the server menu.", nil), NSLocalizedString(@"A certificate identifies you to servers. Generate a new one or import your existing identity.", nil)])[_step];
    UILabel *body = [self labelWithText:detail style:UIFontTextStyleBody];
    body.textColor = UIColor.secondaryLabelColor;
    _headerStack = [[UIStackView alloc] initWithArrangedSubviews:@[symbol, title, body]];
    _headerStack.axis = UILayoutConstraintAxisVertical;
    _headerStack.spacing = 16;
    [self installStack:_headerStack asHeader:YES];

    UIPageControl *pages = [UIPageControl new];
    pages.numberOfPages = 3;
    pages.currentPage = _step;
    pages.userInteractionEnabled = NO;
    pages.currentPageIndicatorTintColor = UIColor.labelColor;
    pages.pageIndicatorTintColor = UIColor.tertiaryLabelColor;
    pages.accessibilityLabel = NSLocalizedString(@"Setup progress", nil);
    _continueButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) configuration = [UIButtonConfiguration prominentGlassButtonConfiguration];
    else
#endif
        configuration = [UIButtonConfiguration filledButtonConfiguration];
    configuration.baseBackgroundColor = UIColor.systemBlueColor;
    configuration.baseForegroundColor = UIColor.whiteColor;
    configuration.title = _step == 2 ? NSLocalizedString(@"Finish", nil) : NSLocalizedString(@"Continue", nil);
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(16, 24, 16, 24);
    _continueButton.configuration = configuration;
    [_continueButton.heightAnchor constraintGreaterThanOrEqualToConstant:50].active = YES;
    [_continueButton addTarget:self action:@selector(continueClicked:) forControlEvents:UIControlEventTouchUpInside];
    if (_step == 2) {
        _certificateStatus = [self labelWithText:nil style:UIFontTextStyleSubheadline];
        UIStackView *status = [[UIStackView alloc] initWithArrangedSubviews:@[_certificateStatus]];
        status.axis = UILayoutConstraintAxisVertical;
        [self installStack:status asHeader:NO];
    }
    _footerStack = [[UIStackView alloc] initWithArrangedSubviews:@[_continueButton, pages]];
    _footerStack.axis = UILayoutConstraintAxisVertical;
    _footerStack.spacing = 12;
    _footerStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_footerStack];
    [NSLayoutConstraint activateConstraints:@[
        [_footerStack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24],
        [_footerStack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24],
        [_footerStack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8]
    ]];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        UIScrollEdgeElementContainerInteraction *edge = [UIScrollEdgeElementContainerInteraction new];
        edge.scrollView = self.tableView;
        edge.edge = UIRectEdgeBottom;
        [_footerStack addInteraction:edge];
        self.tableView.bottomEdgeEffect.style = UIScrollEdgeEffectStyle.softStyle;
    }
#endif
    [self updateCertificateStatus];
}

- (void)installStack:(UIStackView *)stack asHeader:(BOOL)header {
    UIView *container = [UIView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:header ? 32 : 20],
        [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-24]
    ]];
    CGFloat width = MAX(1, self.view.bounds.size.width);
    CGSize measured = [container systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    container.frame = CGRectMake(0, 0, width, ceil(measured.height));
    if (header) self.tableView.tableHeaderView = container;
    else self.tableView.tableFooterView = container;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Measure the scrollable content; the action stays outside the table.
    NSMutableArray *containers = [NSMutableArray array];
    if (self.tableView.tableHeaderView) [containers addObject:self.tableView.tableHeaderView];
    if (self.tableView.tableFooterView) [containers addObject:self.tableView.tableFooterView];
    for (UIView *container in containers) {
        CGFloat width = self.tableView.bounds.size.width;
        if (width <= 0) continue;
        CGSize size = [container systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
        CGRect frame = CGRectMake(0, 0, width, ceil(size.height));
        if (!CGSizeEqualToSize(container.frame.size, frame.size)) {
            container.frame = frame;
            if (container == self.tableView.tableHeaderView) self.tableView.tableHeaderView = container;
            else self.tableView.tableFooterView = container;
        }
    }
    CGFloat bottom = ceil(_footerStack.bounds.size.height) + 24;
    UIEdgeInsets insets = self.tableView.contentInset;
    if (insets.bottom != bottom) {
        insets.bottom = bottom;
        self.tableView.contentInset = insets;
        self.tableView.verticalScrollIndicatorInsets = UIEdgeInsetsMake(0, 0, bottom, 0);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    [self updateCertificateStatus];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _step == 1 ? 3 : _step == 2 ? 2 : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    if (_step == 1) {
        content.text = (@[NSLocalizedString(@"Voice Activated", nil), NSLocalizedString(@"Push-to-talk", nil), NSLocalizedString(@"Continuous", nil)])[indexPath.row];
        content.secondaryText = (@[NSLocalizedString(@"Transmit when your voice is detected.", nil), NSLocalizedString(@"Hold a button while speaking.", nil), NSLocalizedString(@"Transmit whenever the microphone is on.", nil)])[indexPath.row];
        content.image = [UIImage systemImageNamed:(@[@"waveform", @"hand.tap", @"mic.fill"])[indexPath.row]];
        NSString *method = (@[@"vad", @"ptt", @"continuous"])[indexPath.row];
        cell.accessoryType = [[NSUserDefaults.standardUserDefaults stringForKey:@"AudioTransmitMethod"] isEqualToString:method] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else {
        content.text = indexPath.row == 0 ? NSLocalizedString(@"Generate New Certificate", nil) : NSLocalizedString(@"Import Certificates", nil);
        content.image = [UIImage systemImageNamed:indexPath.row == 0 ? @"person.crop.circle.badge.plus" : @"square.and.arrow.down"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    content.textProperties.numberOfLines = 0;
    content.secondaryTextProperties.numberOfLines = 0;
    content.imageProperties.tintColor = UIColor.tintColor;
    cell.contentConfiguration = content;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_step == 1) {
        [(MUApplicationDelegate *)UIApplication.sharedApplication.delegate setAudioTransmitMethod:(@[@"vad", @"ptt", @"continuous"])[indexPath.row]];
        for (NSIndexPath *path in tableView.indexPathsForVisibleRows) {
            [tableView cellForRowAtIndexPath:path].accessoryType = path.row == indexPath.row ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
        return;
    }
    UIViewController *form = indexPath.row == 0 ? (UIViewController *)[MUCertificateCreationView new] : [MUCertificateDiskImportViewController new];
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:form] animated:YES completion:nil];
}

- (void)certificatesChanged:(NSNotification *)notification {
    if (self.isViewLoaded) [self updateCertificateStatus];
}

- (void)updateCertificateStatus {
    if (_step != 2) return;
    MLCertificate *certificate = [MUCertificateController defaultCertificate];
    BOOL ready = certificate.hasPrivateKey;
    _continueButton.enabled = ready;
    _certificateStatus.text = ready ? [NSString stringWithFormat:NSLocalizedString(@"Ready: %@", nil), certificate.subjectName ?: NSLocalizedString(@"Certificate", nil)] : NSLocalizedString(@"Generate or import a certificate to finish setup.", nil);
    _certificateStatus.textColor = ready ? UIColor.labelColor : UIColor.secondaryLabelColor;
    [self.view setNeedsLayout];
}

- (void)continueClicked:(UIButton *)sender {
    if (_finished || self.navigationController.topViewController != self) return;
    if (_step < 2) {
        [self.navigationController pushViewController:[[MUOnboardingViewController alloc] initWithStep:_step + 1 completion:_completion] animated:YES];
        return;
    }
    if (![MUCertificateController defaultCertificate].hasPrivateKey) return;
    _finished = YES;
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:MUInitialSetupCompletedKey];
    if (_completion) _completion();
}

@end
