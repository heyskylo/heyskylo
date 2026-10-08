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

#pragma mark - Plain terminal palette (black background, text only)

static UIColor *TerminalText(void)     { return [UIColor colorWithWhite:0.93 alpha:1]; }
static UIColor *TerminalDim(void)      { return [UIColor colorWithWhite:0.55 alpha:1]; }
static UIColor *TerminalPrompt(void)   { return [UIColor colorWithRed:0.45 green:0.90 blue:0.82 alpha:1]; }
static UIColor *TerminalOutput(void)   { return [UIColor colorWithWhite:0.90 alpha:1]; }
static UIColor *TerminalSuccess(void)  { return [UIColor colorWithRed:0.55 green:0.95 blue:0.60 alpha:1]; }
static UIColor *TerminalFailure(void)  { return [UIColor colorWithRed:1.00 green:0.48 blue:0.48 alpha:1]; }

#pragma mark - Terminal

@interface NXLinuxTerminalViewController () <UITextFieldDelegate>

@property (nonatomic, strong) NSURL *slotURL;

/* Plain terminal UI, like iSH: a black screen, the scrollable transcript, and a
   visible monospaced prompt line (`cwd $ ` + live input) pinned above the
   keyboard. No headers, bars, buttons, or status chrome. */
@property (nonatomic, strong) UITextView *transcript;
@property (nonatomic, strong) UILabel *promptLabel;
@property (nonatomic, strong) UITextField *input;
@property (nonatomic, strong) NSLayoutConstraint *promptLineBottom;

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
    self.view.backgroundColor = UIColor.blackColor;
}

#pragma mark - Boot

- (void)bootGuest
{
    [self appendLine:@"booting an x86-64 Linux guest in a pure-Rust interpreter…\n" color:TerminalDim()];

    NSString *kernelPath = [self.slotURL.path stringByAppendingPathComponent:[@"kernel" stringByAppendingPathComponent:NXLinuxKernelName]];
    NSString *initramfsPath = [self.slotURL.path stringByAppendingPathComponent:[@"initramfs" stringByAppendingPathComponent:NXLinuxInitrdName]];

    BOOL kernelOK = [NSFileManager.defaultManager isReadableFileAtPath:kernelPath];
    BOOL initrdOK = [NSFileManager.defaultManager isReadableFileAtPath:initramfsPath];
    if(!kernelOK || !initrdOK)
    {
        [self appendLine:@"error: Linux boot assets missing from slot\n" color:TerminalFailure()];
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
                           color:TerminalSuccess()];
                [self setLive:YES status:@"live"];
                [self runInitialEvidence];
            }
            else
            {
                [self appendLine:@"the guest failed to boot\n" color:TerminalFailure()];
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
                if(out.length > 0) [self appendLine:out color:TerminalOutput()];
                if(err.length > 0) [self appendLine:err color:TerminalFailure()];
            }
            else
            {
                [self appendLine:[NSString stringWithFormat:@"(kernel evidence failed: %@)\n", error.localizedDescription ?: @"unknown error"]
                           color:TerminalFailure()];
            }
            [self appendLine:@"try:  cat /proc/cpuinfo  ·  ls /  ·  ps  ·  echo hi\n\n" color:TerminalDim()];
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
    [self appendLine:[NSString stringWithFormat:@"%@ $ %@\n", self.cwd, text] color:TerminalPrompt()];
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
                           color:TerminalFailure()];
                return;
            }
            NSString *stdoutString = out ?: @"";
            NSString *guestDir = [self takeCwdFrom:&stdoutString marker:marker];
            if(guestDir.length > 0)
            {
                self.cwd = guestDir;
                [self updatePrompt];
            }
            if(stdoutString.length > 0)
            {
                [self appendLine:stdoutString color:TerminalOutput()];
            }
            if(err.length > 0)
            {
                [self appendLine:err color:TerminalFailure()];
            }
            if(stdoutString.length == 0 && err.length == 0)
            {
                [self appendLine:@"(no output)\n" color:TerminalDim()];
            }
            else if(![stdoutString hasSuffix:@"\n"] && ![err hasSuffix:@"\n"])
            {
                [self appendLine:@"\n" color:TerminalOutput()];
            }
            if(exitCode != 0)
            {
                [self appendLine:[NSString stringWithFormat:@"[exit %d]\n", exitCode] color:TerminalDim()];
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

#pragma mark - UI (iSH-style terminal)

- (void)updatePrompt
{
    self.promptLabel.text = [NSString stringWithFormat:@"%@ $ ", self.cwd];
}

- (void)buildUI
{
    self.view.backgroundColor = UIColor.blackColor;

    /* Transcript: the scrollable boot + command output history. */
    self.transcript = [UITextView new];
    self.transcript.backgroundColor = [UIColor clearColor];
    self.transcript.editable = NO;
    self.transcript.selectable = NO;
    self.transcript.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.transcript.textColor = TerminalText();
    self.transcript.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    self.transcript.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.transcript];

    /* Prompt line: `cwd $ ` + live input, plain monospaced text on black with
       no background or border, pinned just above the keyboard so you can see
       what you type. */
    self.promptLabel = [UILabel new];
    self.promptLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightBold];
    self.promptLabel.textColor = TerminalPrompt();
    self.promptLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.promptLabel];

    self.input = [UITextField new];
    self.input.backgroundColor = UIColor.clearColor;
    self.input.borderStyle = UITextBorderStyleNone;
    self.input.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.input.textColor = TerminalText();
    self.input.tintColor = TerminalText();
    self.input.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.input.autocorrectionType = UITextAutocorrectionTypeNo;
    self.input.spellCheckingType = UITextSpellCheckingTypeNo;
    self.input.smartQuotesType = UITextSmartQuotesTypeNo;
    self.input.keyboardType = UIKeyboardTypeASCIICapable;
    self.input.returnKeyType = UIReturnKeyGo;
    self.input.enabled = NO;
    self.input.delegate = self;
    [self.input setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    self.input.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.input];

    [self updatePrompt];

    self.promptLineBottom = [self.input.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8];

    [NSLayoutConstraint activateConstraints:@[
        [self.transcript.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.transcript.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.transcript.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.transcript.bottomAnchor constraintEqualToAnchor:self.input.topAnchor constant:-6],

        [self.promptLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.promptLabel.centerYAnchor constraintEqualToAnchor:self.input.centerYAnchor],
        [self.promptLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.input.leadingAnchor constant:-6],

        [self.input.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        self.promptLineBottom,
        [self.input.heightAnchor constraintEqualToConstant:30],
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusInput)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];
}

- (void)focusInput
{
    if(self.live && self.input.enabled)
    {
        [self.input becomeFirstResponder];
    }
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
    self.promptLineBottom.constant = -(overlap + 8);
    [self.view layoutIfNeeded];
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
    self.input.enabled = live;
    if(live)
    {
        [self.input becomeFirstResponder];
    }
    (void)status;
}

- (void)setBusy:(BOOL)busy
{
    self.input.enabled = !busy;
    if(!busy)
    {
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
                 NSFontAttributeName: [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular],
                 NSForegroundColorAttributeName: color,
             }]];
    self.transcript.attributedText = attr;
    [self.transcript scrollRangeToVisible:NSMakeRange(attr.length, 0)];
}

@end