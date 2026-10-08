/*
 SPDX-License-Identifier: GPL-2.0-or-later

 Boot flow, per spec: on load, check whether the pinned postmarketOS image is
 staged → if not, show a Download button → download+verify+decompress (thin
 progress bar at the very top, nothing else) → boot the VM → full-screen
 Phosh surface with direct touch. No gamepad, no keyboard buttons, no window
 bars anywhere.
*/

#import "NXPostmarketOSViewController.h"
#import "NXGuestImageManager.h"
#import "NXPMOSEngine.h"
#import "NXSurfaceView.h"
#import "NXBootState.h"

@interface NXPostmarketOSViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NXGuestImageManager *imageManager;
@property (nonatomic, strong) NXPMOSEngine *engine;
@property (nonatomic, assign) NXBootState state;
@property (nonatomic, copy) void (^actionHandler)(void);
@property (nonatomic, strong) UIProgressView *progressBar;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) NXSurfaceView *surfaceView;
@property (nonatomic, assign) BOOL started;
@end

@implementation NXPostmarketOSViewController

- (instancetype)initWithSlotURL:(NSURL *)slotURL
{
    self = [super initWithNibName:nil bundle:nil];
    if (self)
    {
        _imageManager = [[NXGuestImageManager alloc] initWithSlotURL:slotURL];
    }
    return self;
}

- (void)loadView
{
    self.view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.backgroundColor = [UIColor blackColor];
    self.view.userInteractionEnabled = YES;

    _surfaceView = [[NXSurfaceView alloc] initWithFrame:self.view.bounds];
    _surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
    _surfaceView.hidden = YES;
    [self.view addSubview:_surfaceView];

    _progressBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    _progressBar.hidden = YES;
    _progressBar.trackTintColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    _progressBar.progressTintColor = [UIColor colorWithRed:0.35 green:0.85 blue:0.55 alpha:1.0];
    [self.view addSubview:_progressBar];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.numberOfLines = 0;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    _statusLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.color = [UIColor colorWithWhite:0.95 alpha:1.0];

    _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    _actionButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _actionButton.backgroundColor = [UIColor colorWithRed:0.55 green:0.85 blue:0.62 alpha:1.0];
    [_actionButton setTitleColor:[UIColor colorWithWhite:0.05 alpha:1.0] forState:UIControlStateNormal];
    _actionButton.layer.cornerRadius = 12;
    _actionButton.layer.masksToBounds = YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    _actionButton.contentEdgeInsets = UIEdgeInsetsMake(12, 24, 12, 24);
#pragma clang diagnostic pop
    _actionButton.hidden = YES;
    [_actionButton addTarget:self action:@selector(actionButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[_statusLabel, _spinner, _actionButton]];
    column.translatesAutoresizingMaskIntoConstraints = NO;
    column.axis = UILayoutConstraintAxisVertical;
    column.alignment = UIStackViewAlignmentCenter;
    column.distribution = UIStackViewDistributionFill;
    column.spacing = 20;
    [self.view addSubview:column];

    [NSLayoutConstraint activateConstraints:@[
        [_surfaceView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_surfaceView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_surfaceView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_surfaceView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [_progressBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_progressBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_progressBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_progressBar.heightAnchor constraintEqualToConstant:4],

        [column.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [column.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [column.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [column.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
    ]];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!self.started)
    {
        self.started = YES;
        [self checkImage];
    }
}

#pragma mark - Boot flow

- (void)checkImage
{
    self.state = NXBootStateChecking;
    [self configureUIWithMessage:@"checking for a staged postmarketOS image…"
                         spinner:YES
                        progress:-1.0
                     buttonTitle:nil
                            action:nil];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL staged = [weakSelf.imageManager hasPinnedImage];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!staged)
            {
                [weakSelf showDownloadGate];
            }
            else
            {
                [weakSelf bootGuest];
            }
        });
    });
}

- (void)showDownloadGate
{
    self.state = NXBootStateNeedsDownload;
    __weak typeof(self) weakSelf = self;
    [self configureUIWithMessage:@"postmarketOS · Phosh\nno image staged in the slot yet"
                         spinner:NO
                        progress:-1.0
                     buttonTitle:@"Download postmarketOS image (1.4 GB)"
                            action:^{ [weakSelf beginDownload]; }];
}

- (void)beginDownload
{
    self.state = NXBootStateDownloading;
    self.progressBar.hidden = NO;
    [self configureUIWithMessage:@"downloading…"
                         spinner:YES
                        progress:0.0
                     buttonTitle:nil
                            action:nil];

    __weak typeof(self) weakSelf = self;
    [self.imageManager beginWithProgress:^(NSString *phase, double progress) {
        [weakSelf handleDownloadPhase:phase progress:progress];
    } completion:^(NSError * _Nullable error) {
        [weakSelf handleDownloadCompletion:error];
    }];
}

- (void)handleDownloadPhase:(NSString *)phase progress:(double)progress
{
    NSString *message;
    if ([phase isEqualToString:@"downloading"])
    {
        message = (progress >= 0)
            ? [NSString stringWithFormat:@"downloading… %.0f%%", progress * 100.0]
            : @"downloading…";
    }
    else if ([phase isEqualToString:@"verifying"])
    {
        message = @"verifying SHA-256 against lockfile…";
    }
    else if ([phase isEqualToString:@"decompressing"])
    {
        message = (progress >= 0)
            ? [NSString stringWithFormat:@"decompressing… %.0f%%", progress * 100.0]
            : @"decompressing…";
    }
    else
    {
        message = phase;
    }

    [self configureUIWithMessage:message
                         spinner:(progress < 0)
                        progress:(progress < 0 ? 0.0 : progress)
                     buttonTitle:nil
                            action:nil];
}

- (void)handleDownloadCompletion:(NSError * _Nullable)error
{
    if (error == nil)
    {
        [self bootGuest];
        return;
    }
    if (error.code == NXGuestImageErrorCancelled)
    {
        [self showDownloadGate];
        return;
    }
    [self showFailureWithMessage:error.localizedDescription];
}

- (void)bootGuest
{
    NSString *diskPath = [self.imageManager stagedImagePath];
    if (diskPath == nil)
    {
        [self showFailureWithMessage:@"staged image is missing — re-download it"];
        return;
    }

    self.state = NXBootStateBooting;
    self.progressBar.hidden = YES;
    [self configureUIWithMessage:@"booting postmarketOS…"
                         spinner:YES
                        progress:-1.0
                     buttonTitle:nil
                            action:nil];

    self.engine = [[NXPMOSEngine alloc] initWithDiskPath:diskPath memoryMiB:4096];
    if (!self.engine.isAvailable)
    {
        [self showEngineUnavailable];
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        NSError *error = nil;
        BOOL ok = [weakSelf.engine startWithError:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf == nil)
            {
                return;
            }
            if (ok)
            {
                [weakSelf showRunning];
            }
            else if (error != nil && error.code == NXPMOSEngineErrorBootDriver)
            {
                /* Engine library present but boot driver not wired yet. */
                [weakSelf configureUIWithMessage:error.localizedDescription
                                         spinner:NO
                                        progress:-1.0
                                     buttonTitle:@"Recheck"
                                            action:^{ [weakSelf checkImage]; }];
            }
            else
            {
                [weakSelf showFailureWithMessage:(error != nil ? error.localizedDescription
                                                              : @"the engine stopped unexpectedly")];
            }
        });
    });
}

- (void)showRunning
{
    self.state = NXBootStateRunning;
    self.progressBar.hidden = YES;
    self.statusLabel.hidden = YES;
    [self.spinner stopAnimating];
    self.spinner.hidden = YES;
    self.actionButton.hidden = YES;
    self.surfaceView.hidden = NO;
    [self.view setNeedsLayout];
}

- (void)showEngineUnavailable
{
    self.state = NXBootStateEngineUnavailable;
    __weak typeof(self) weakSelf = self;
    [self configureUIWithMessage:@"The QEMU JIT engine is not bundled in this ROM build yet.\n\n"
                                  @"The downloader, verifier, and decoder are in place and the staged "
                                  @"guest is ready — the engine milestone builds libqemu-x86_64-softmmu "
                                  @"and ships it in the slot Frameworks directory."
                         spinner:NO
                        progress:-1.0
                     buttonTitle:@"Recheck image"
                            action:^{ [weakSelf checkImage]; }];
}

- (void)showFailureWithMessage:(NSString *)message
{
    self.state = NXBootStateFailed;
    __weak typeof(self) weakSelf = self;
    [self configureUIWithMessage:[NSString stringWithFormat:@"Something went wrong\n\n%@", message]
                         spinner:NO
                        progress:-1.0
                     buttonTitle:@"Retry"
                            action:^{ [weakSelf checkImage]; }];
}

#pragma mark - UI helpers

- (void)configureUIWithMessage:(NSString *)message
                       spinner:(BOOL)showSpinner
                      progress:(double)progress
                   buttonTitle:(NSString * _Nullable)buttonTitle
                        action:(void (^ _Nullable)(void))action
{
    self.statusLabel.text = message;
    self.statusLabel.hidden = NO;

    if (showSpinner)
    {
        [self.spinner startAnimating];
    }
    else
    {
        [self.spinner stopAnimating];
    }

    self.progressBar.hidden = (progress < 0);
    if (progress >= 0)
    {
        self.progressBar.progress = (float)MIN(1.0, progress);
    }

    self.actionButton.hidden = (buttonTitle == nil);
    self.actionHandler = action;
    if (buttonTitle != nil)
    {
        [self.actionButton setTitle:buttonTitle forState:UIControlStateNormal];
    }
}

- (void)actionButtonTapped
{
    if (self.actionHandler != nil)
    {
        self.actionHandler();
    }
}

@end