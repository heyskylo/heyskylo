/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

#import "NXLinuxTerminalViewController.h"
#import "NXRish.h"

static NSString * const NXLinuxCommandLine =
    @"console=ttyS0,115200n8 rdinit=/init panic=-1 oops=panic nokaslr "
    @"cgroup_no_v1=all 8250.nr_uarts=1";

static NSString * const NXLinuxKernelName = @"vmlinuz-virt-6.18.35";
static NSString * const NXLinuxInitrdName = @"rish-container.cpio";
static NSString * const NXLinuxMemoryDefaultsKey = @"nyxian.boot.linux.memoryMB";

/* record separator (U+001E) used to recover the guest's cwd after each command.
   "\u001E" would be a universal character name for a control character, which
   the C standard forbids; "\x1E" is the identical single UTF-8 byte. */
static NSString * const NXRishCwdMark = @"\x1E";

#pragma mark - Theme

static UIColor *ThemeBgTop(void)   { return [UIColor colorWithRed:0.04 green:0.06 blue:0.13 alpha:1]; }
static UIColor *ThemeBgBottom(void){ return [UIColor colorWithRed:0.02 green:0.03 blue:0.07 alpha:1]; }
static UIColor *ThemeTerminal(void){ return [UIColor colorWithRed:0.02 green:0.04 blue:0.08 alpha:1]; }
static UIColor *ThemeInputBar(void){ return [UIColor colorWithRed:0.07 green:0.10 blue:0.18 alpha:1]; }
static UIColor *ThemeBorder(void)  { return [UIColor colorWithRed:0.16 green:0.22 blue:0.34 alpha:1]; }
static UIColor *ThemePrimary(void) { return [UIColor colorWithRed:0.94 green:0.96 blue:0.99 alpha:1]; }
static UIColor *ThemeSecondary(void){return [UIColor colorWithRed:0.58 green:0.64 blue:0.75 alpha:1]; }
static UIColor *ThemePrompt(void)  { return [UIColor colorWithRed:0.37 green:0.92 blue:0.83 alpha:1]; }
static UIColor *ThemeOutput(void)  { return [UIColor colorWithRed:0.80 green:0.88 blue:0.97 alpha:1]; }
static UIColor *ThemeSuccess(void) { return [UIColor colorWithRed:0.49 green:0.90 blue:0.53 alpha:1]; }
static UIColor *ThemeFailure(void) { return [UIColor colorWithRed:0.97 green:0.45 blue:0.45 alpha:1]; }
static UIColor *ThemeAccent(void)  { return [UIColor colorWithRed:0.37 green:0.92 blue:0.83 alpha:1]; }

#pragma mark - Terminal

@interface NXLinuxTerminalViewController () <UITextFieldDelegate>

@property (nonatomic, strong) NSURL *slotURL;

@property (nonatomic, strong) UITextView *transcript;
@property (nonatomic, strong) UITextField *input;
@property (nonatomic, strong) UIButton *runButton;
@property (nonatomic, strong) UILabel *statusPill;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSLayoutConstraint *inputBarBottom;

@property (nonatomic, strong) NXRish *session;
@property (nonatomic, strong) NSDate *bootStart;
@property (nonatomic, copy) NSString *cwd;
@property (nonatomic, assign) BOOL live;

@end

@implementation NXLinuxTerminalViewController

- (instancetype)initWithSlotURL:(NSURL *)slotURL
{
    self = [super initWithNibName:nil bundle:nil];
    if(self)
    {
        _slotURL = slotURL;
        _cwd = @"/";
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self buildUI];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(keyboardWillChange:)
                                               name:UIKeyboardWillChangeFrameNotification
                                             object:nil];
    [self bootGuest];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.view.backgroundColor = ThemeBgTop();
}

#pragma mark - Boot

- (void)bootGuest
{
    [self appendLine:@"booting an x86-64 Linux guest in a pure-Rust interpreter…\n" color:ThemeSecondary()];

    NSString *kernelPath = [self.slotURL.path stringByAppendingPathComponent:[@"kernel" stringByAppendingPathComponent:NXLinuxKernelName]];
    NSString *initramfsPath = [self.slotURL.path stringByAppendingPathComponent:[@"initramfs" stringByAppendingPathComponent:NXLinuxInitrdName]];

    BOOL kernelOK = [NSFileManager.defaultManager isReadableFileAtPath:kernelPath];
    BOOL initrdOK = [NSFileManager.defaultManager isReadableFileAtPath:initramfsPath];
    if(!kernelOK || !initrdOK)
    {
        [self appendLine:@"error: Linux boot assets missing from slot\n" color:ThemeFailure()];
        [self setLive:NO status:@"missing"];
        return;
    }

    NSNumber *memory = [NSUserDefaults.standardUserDefaults objectForKey:NXLinuxMemoryDefaultsKey];
    NSUInteger memoryMiB = [memory isKindOfClass:NSNumber.class] ? memory.unsignedIntegerValue : 1024;

    self.bootStart = [NSDate date];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NXRish *session = [[NXRish alloc] initWithKernelPath:kernelPath
                                               initramfsPath:initramfsPath
                                                    memoryMiB:memoryMiB
                                                 commandLine:NXLinuxCommandLine];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(self) self = weakSelf;
            if(!self)
            {
                return;
            }
            if(session)
            {
                self.session = session;
                NSTimeInterval secs = [NSDate.date timeIntervalSinceDate:self.bootStart];
                [self appendLine:[NSString stringWithFormat:@"guest is up in %.0fs — real x86-64 Linux, JIT-less, isolated from iOS\n", secs]
                           color:ThemeSuccess()];
                [self setLive:YES status:@"live"];
                [self runInitialEvidence];
            }
            else
            {
                [self appendLine:@"the guest failed to boot\n" color:ThemeFailure()];
                [self setLive:NO status:@"failed"];
            }
        });
    });
}

/* Show the kernel actually booted: identify it and dump the kernel log. */
- (void)runInitialEvidence
{
    NSString *script =
        @"mount -t proc proc /proc 2>/dev/null; "
        @"mount -t sysfs sysfs /sys 2>/dev/null; "
        @"uname -a; "
        @"printf '\\n--- kernel log (dmesg tail) ---\\n'; "
        @"dmesg 2>/dev/null | tail -120 || true";

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __strong typeof(self) self = weakSelf;
        if(!self)
        {
            return;
        }
        NSString *out = nil, *err = nil;
        int exitCode = 0;
        NSError *error = nil;
        BOOL ok = [self.session runCommandWithArguments:@[ @"sh", @"-lc", script ]
                                                    cwd:@"/"
                                              timeoutMS:60000
                                                 stdout:&out stderr:&err
                                               exitCode:&exitCode error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if(ok)
            {
                if(out.length > 0) [self appendLine:out color:ThemeOutput()];
                if(err.length > 0) [self appendLine:err color:ThemeFailure()];
            }
            else
            {
                [self appendLine:[NSString stringWithFormat:@"(kernel evidence failed: %@)\n", error.localizedDescription ?: @"unknown error"]
                           color:ThemeFailure()];
            }
            [self appendLine:@"try:  cat /proc/cpuinfo  ·  ls /  ·  ps  ·  echo hi\n\n" color:ThemeSecondary()];
        });
    });
}

#pragma mark - Command execution

- (void)submit
{
    NSString *text = [self.input.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if(text.length == 0)
    {
        return;
    }
    self.input.text = @"";
    [self executeCommand:text];
}

- (void)executeCommand:(NSString *)text
{
    if(!self.session)
    {
        return;
    }
    [self appendLine:[NSString stringWithFormat:@"%@ $ %@\n", self.cwd, text] color:ThemePrompt()];
    [self setBusy:YES];

    NSString *dir = [self.cwd copy];
    NSString *marker = NXRishCwdMark;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __strong typeof(self) self = weakSelf;
        if(!self)
        {
            return;
        }
        /* Each command runs a fresh `sh`, so we remount proc/sysfs (idempotent),
         * cd into the tracked guest directory, run, then report the resulting
         * pwd through a record-separator marker we strip from the output. */
        NSString *setup = @"mount -t proc proc /proc 2>/dev/null; mount -t sysfs sysfs /sys 2>/dev/null";
        NSString *script = [NSString stringWithFormat:
            @"%@\ncd '%@' 2>/dev/null\n%@\n__rish_rc=$?\n"
            @"printf '%@%%s%@' \"$(pwd)\"\nexit $__rish_rc",
            setup, dir, text, marker, marker];

        NSString *out = nil, *err = nil;
        int exitCode = 0;
        NSError *error = nil;
        BOOL ok = [self.session runCommandWithArguments:@[ @"sh", @"-lc", script ]
                                                    cwd:@"/"
                                              timeoutMS:60000
                                                 stdout:&out stderr:&err
                                               exitCode:&exitCode error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO];
            if(!ok)
            {
                [self appendLine:[NSString stringWithFormat:@"command failed: %@\n", error.localizedDescription ?: @"unknown error"]
                           color:ThemeFailure()];
                return;
            }
            NSString *stdoutString = out ?: @"";
            NSString *guestDir = [self takeCwdFrom:&stdoutString marker:marker];
            if(guestDir.length > 0)
            {
                self.cwd = guestDir;
            }
            if(stdoutString.length > 0)
            {
                [self appendLine:stdoutString color:ThemeOutput()];
            }
            if(err.length > 0)
            {
                [self appendLine:err color:ThemeFailure()];
            }
            if(stdoutString.length == 0 && err.length == 0)
            {
                [self appendLine:@"(no output)\n" color:ThemeSecondary()];
            }
            else if(![stdoutString hasSuffix:@"\n"] && ![err hasSuffix:@"\n"])
            {
                [self appendLine:@"\n" color:ThemeOutput()];
            }
            if(exitCode != 0)
            {
                [self appendLine:[NSString stringWithFormat:@"[exit %d]\n", exitCode] color:ThemeSecondary()];
            }
        });
    });
}

- (NSString *)takeCwdFrom:(NSString * _Nonnull * _Nonnull)output marker:(NSString *)marker
{
    if(*output == nil)
    {
        return nil;
    }
    NSMutableString *string = [*output mutableCopy];
    NSRange first = [string rangeOfString:marker];
    if(first.location == NSNotFound)
    {
        return nil;
    }
    NSRange tail = NSMakeRange(NSMaxRange(first), string.length - NSMaxRange(first));
    NSRange second = [string rangeOfString:marker options:0 range:tail];
    if(second.location == NSNotFound)
    {
        return nil;
    }
    NSString *dir = [string substringWithRange:NSMakeRange(NSMaxRange(first), second.location - NSMaxRange(first))];
    [string deleteCharactersInRange:NSMakeRange(first.location, NSMaxRange(second) - first.location)];
    *output = [string copy];
    return dir;
}

#pragma mark - UI

- (void)buildUI
{
    self.view.backgroundColor = ThemeBgTop();

    UIView *header = [self makeHeader];
    UIView *terminalCard = [self makeTerminalCard];
    UIView *inputBar = [self makeInputBar];
    for(UIView *v in @[header, terminalCard, inputBar])
    {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:v];
    }

    self.inputBarBottom = [inputBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [terminalCard.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:14],
        [terminalCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
        [terminalCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [terminalCard.bottomAnchor constraintEqualToAnchor:inputBar.topAnchor constant:-12],

        [inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
        [inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        self.inputBarBottom,
    ]];
}

- (UIView *)makeHeader
{
    UILabel *title = [UILabel new];
    UIFont *bold = [UIFont systemFontOfSize:26 weight:UIFontWeightHeavy];
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc]
        initWithString:@"Linux" attributes:@{ NSFontAttributeName: bold, NSForegroundColorAttributeName: ThemePrimary() }];
    [attributed appendAttributedString:[[NSAttributedString alloc]
        initWithString:@"\u25CF" attributes:@{ NSFontAttributeName: bold, NSForegroundColorAttributeName: ThemeAccent() }]];
    title.attributedText = attributed;

    UILabel *subtitle = [UILabel new];
    subtitle.text = @"x86-64 Linux kernel, JIT-less, on iOS";
    subtitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    subtitle.textColor = ThemeSecondary();

    self.statusPill = [UILabel new];
    self.statusPill.text = @"booting…";
    self.statusPill.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    self.statusPill.textColor = ThemeSecondary();
    self.statusPill.backgroundColor = [ThemeSecondary() colorWithAlphaComponent:0.14];
    self.statusPill.layer.cornerRadius = 9;
    self.statusPill.clipsToBounds = YES;
    self.statusPill.textAlignment = NSTextAlignmentCenter;
    [self.statusPill setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.statusPill.widthAnchor constraintEqualToConstant:76].active = YES;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = ThemeAccent();
    [self.spinner startAnimating];
    [self.spinner setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *left = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle]];
    left.axis = UILayoutConstraintAxisVertical;
    left.spacing = 2;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[left, self.spinner, self.statusPill]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.alignment = UIStackViewAlignmentCenter;
    return row;
}

- (UIView *)makeTerminalCard
{
    UIView *card = [UIView new];
    card.backgroundColor = ThemeTerminal();
    card.layer.cornerRadius = 16;
    card.layer.borderWidth = 1;
    card.layer.borderColor = ThemeBorder().CGColor;
    card.clipsToBounds = YES;

    UIView *dotsRow = [UIView new];
    dotsRow.backgroundColor = [UIColor clearColor];
    for(UIColor *color in @[UIColor.systemRedColor, UIColor.systemYellowColor, UIColor.systemGreenColor])
    {
        UIView *dot = [UIView new];
        dot.backgroundColor = [color colorWithAlphaComponent:0.85];
        dot.layer.cornerRadius = 5;
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        [dot.widthAnchor constraintEqualToConstant:10].active = YES;
        [dot.heightAnchor constraintEqualToConstant:10].active = YES;
        [dotsRow addSubview:dot];
    }
    // stack the three dots
    UIStackView *dots = [[UIStackView alloc] initWithArrangedSubviews:dotsRow.subviews];
    dots.axis = UILayoutConstraintAxisHorizontal;
    dots.spacing = 7;

    UILabel *barTitle = [UILabel new];
    barTitle.text = @"root@linux";
    barTitle.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
    barTitle.textColor = ThemeSecondary();

    UIStackView *titleBar = [[UIStackView alloc] initWithArrangedSubviews:@[dots, barTitle, [UIView new]]];
    titleBar.axis = UILayoutConstraintAxisHorizontal;
    titleBar.spacing = 10;
    titleBar.alignment = UIStackViewAlignmentCenter;
    titleBar.translatesAutoresizingMaskIntoConstraints = NO;

    self.transcript = [UITextView new];
    self.transcript.backgroundColor = [UIColor clearColor];
    self.transcript.editable = NO;
    self.transcript.selectable = YES;
    self.transcript.font = [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightRegular];
    self.transcript.textColor = ThemeOutput();
    self.transcript.textContainerInset = UIEdgeInsetsMake(8, 4, 8, 4);
    self.transcript.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *sep = [UIView new];
    sep.backgroundColor = ThemeBorder();
    sep.translatesAutoresizingMaskIntoConstraints = NO;

    [card addSubview:titleBar];
    [card addSubview:sep];
    [card addSubview:self.transcript];
    [NSLayoutConstraint activateConstraints:@[
        [titleBar.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [titleBar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [titleBar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],

        [sep.topAnchor constraintEqualToAnchor:titleBar.bottomAnchor constant:10],
        [sep.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [sep.heightAnchor constraintEqualToConstant:1],

        [self.transcript.topAnchor constraintEqualToAnchor:sep.bottomAnchor],
        [self.transcript.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:10],
        [self.transcript.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10],
        [self.transcript.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-8],
    ]];
    return card;
}

- (UIView *)makeInputBar
{
    UIView *bar = [UIView new];
    bar.backgroundColor = ThemeInputBar();
    bar.layer.cornerRadius = 14;
    bar.layer.borderWidth = 1;
    bar.layer.borderColor = ThemeBorder().CGColor;

    UILabel *prompt = [UILabel new];
    prompt.text = @"$";
    prompt.font = [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightBold];
    prompt.textColor = ThemePrompt();

    self.input = [UITextField new];
    self.input.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.input.textColor = ThemePrimary();
    self.input.tintColor = ThemeAccent();
    self.input.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.input.autocorrectionType = UITextAutocorrectionTypeNo;
    self.input.spellCheckingType = UITextSpellCheckingTypeNo;
    self.input.smartQuotesType = UITextSmartQuotesTypeNo;
    self.input.keyboardType = UIKeyboardTypeASCIICapable;
    self.input.returnKeyType = UIReturnKeyGo;
    self.input.enabled = NO;
    self.input.delegate = self;
    self.input.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:@"booting the guest…"
            attributes:@{ NSForegroundColorAttributeName: ThemeSecondary() }];

    self.runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.runButton setTitle:@"Run" forState:UIControlStateNormal];
    self.runButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    [self.runButton setTitleColor:ThemeBgBottom() forState:UIControlStateNormal];
    self.runButton.backgroundColor = ThemeAccent();
    self.runButton.layer.cornerRadius = 10;
    self.runButton.contentEdgeInsets = UIEdgeInsetsMake(8, 16, 8, 16);
    self.runButton.enabled = NO;
    self.runButton.alpha = 0.5;
    [self.runButton addTarget:self action:@selector(runTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.runButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[prompt, self.input, self.runButton]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 10;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    [bar addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:bar.topAnchor constant:8],
        [row.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:14],
        [row.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-10],
        [row.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-8],
    ]];
    return bar;
}

- (void)runTapped:(UIButton *)sender
{
    [self submit];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self submit];
    return NO;
}

#pragma mark - State

- (void)setLive:(BOOL)live status:(NSString *)status
{
    _live = live;
    [self.spinner stopAnimating];
    self.statusPill.text = status;
    self.statusPill.textColor = live ? ThemeSuccess() : ThemeFailure();
    self.statusPill.backgroundColor = [(live ? ThemeSuccess() : ThemeFailure()) colorWithAlphaComponent:0.16];
    self.input.enabled = live;
    self.runButton.enabled = live;
    self.runButton.alpha = live ? 1.0 : 0.5;
    self.input.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:live ? @"type a shell command…" : @"guest unavailable"
            attributes:@{ NSForegroundColorAttributeName: ThemeSecondary() }];
    if(live)
    {
        [self.input becomeFirstResponder];
    }
}

- (void)setBusy:(BOOL)busy
{
    self.input.enabled = !busy;
    self.runButton.enabled = !busy;
    self.runButton.alpha = busy ? 0.5 : 1.0;
    if(busy)
    {
        [self.spinner startAnimating];
    }
    else
    {
        [self.spinner stopAnimating];
        [self.input becomeFirstResponder];
    }
}

- (void)appendLine:(NSString *)text color:(UIColor *)color
{
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc]
        initWithAttributedString:self.transcript.attributedText ?: [[NSAttributedString alloc] init]];
    [attr appendAttributedString:[[NSAttributedString alloc]
        initWithString:text
             attributes:@{
                 NSFontAttributeName: [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightRegular],
                 NSForegroundColorAttributeName: color,
             }]];
    self.transcript.attributedText = attr;
    [self.transcript scrollRangeToVisible:NSMakeRange(attr.length, 0)];
}

- (void)keyboardWillChange:(NSNotification *)notification
{
    NSValue *frameValue = notification.userInfo[UIKeyboardFrameEndUserInfoKey];
    if(![frameValue isKindOfClass:NSValue.class])
    {
        return;
    }
    CGRect keyboard = [self.view convertRect:frameValue.CGRectValue fromView:nil];
    CGFloat overlap = MAX(0, self.view.bounds.size.height - CGRectGetMinY(keyboard) - self.view.safeAreaInsets.bottom);
    self.inputBarBottom.constant = -(overlap + 10);
    [self.view layoutIfNeeded];
}

@end