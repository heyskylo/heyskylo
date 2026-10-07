#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <errno.h>
#import <string.h>
#include <limits.h>
#include <stdlib.h>
#import <LindChain/IDEFoundation/NXBootstrap.h>
#import <LindChain/ProcEnvironment/PEUserspaceManager.h>
#import <LindChain/ProcEnvironment/PEProcessManager.h>
#import <LindChain/Services/bootstrapd/LDEApplicationObject.h>
#import <LindChain/ProcEnvironment/Surface/trust/trust.h>
#import <LindChain/ProcEnvironment/Surface/libkern/klog.h>
#import <LindChain/WindowServer/NXWindowServer.h>
#import <LindChain/WindowServer/Session/NXWindowSessionApplication.h>

static BOOL NXROMDefaultBool(NSString *key, BOOL fallback)
{
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return value ? [value boolValue] : fallback;
}

static LDEApplicationObject *NXROMLocalApplicationObject(NSString *helloPath)
{
    NSString *bundlePath = [helloPath stringByDeletingLastPathComponent];
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    
    if(bundle == nil || bundle.bundleIdentifier.length == 0)
    {
        char resolvedBundle[PATH_MAX];
        if(realpath(bundlePath.fileSystemRepresentation, resolvedBundle) != NULL)
        {
            NSString *physicalBundlePath = [NSString stringWithUTF8String:resolvedBundle];
            bundle = [NSBundle bundleWithPath:physicalBundlePath];
        }
    }
    
    if(bundle == nil || bundle.bundleIdentifier.length == 0)
    {
        return nil;
    }
    return [[LDEApplicationObject alloc] initWithNSBundle:bundle];
}

static void NXROMLaunchHelloPoC(void)
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *helloPath = [NXBootstrap.shared.rootfsURL.path stringByAppendingPathComponent:@"Application/Hello.app/Hello"];
        if(![NSFileManager.defaultManager isReadableFileAtPath:helloPath])
        {
            return;
        }
        
        LDEApplicationObject *application = NXROMLocalApplicationObject(helloPath);
        if(application == nil || application.bundleIdentifier.length == 0)
        {
            return;
        }
        
        NSDictionary *items = @{
            @"PEExecutablePath": helloPath,
            @"PEArguments": @[ helloPath ],
            @"PEWorkingDirectory": NXBootstrap.shared.rootfsURL.path,
            @"PEEnvironment": @{},
        };
        
        pid_t pid = [[PEProcessManager shared] spawnProcessWithItems:items withKernelSurfaceProcess:NULL];
        if(pid < 0)
        {
            return;
        }
        
        PEProcess *process = [[PEProcessManager shared] processForProcessIdentifier:pid];
        if(process != nil)
        {
            process.applicationObject = application;
            process.bundleIdentifier = application.bundleIdentifier;
            process.displayName = application.localizedName.length > 0 ? application.localizedName : @"Hello";
        }
    });
}

@interface NXROMRootViewController : UIViewController
@end

@implementation NXROMRootViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    
    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"ROM";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    title.textAlignment = NSTextAlignmentCenter;
    
    UIButton *launch = [UIButton buttonWithType:UIButtonTypeSystem];
    launch.translatesAutoresizingMaskIntoConstraints = NO;
    [launch setTitle:@"Launch Hello.app" forState:UIControlStateNormal];
    launch.titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
    launch.contentEdgeInsets = UIEdgeInsetsMake(12.0, 22.0, 12.0, 22.0);
    [launch addTarget:self action:@selector(launchHelloTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIButton *showAppSwitcher = [UIButton buttonWithType:UIButtonTypeSystem];
    showAppSwitcher.translatesAutoresizingMaskIntoConstraints = NO;
    [showAppSwitcher setTitle:@"Show App Switcher" forState:UIControlStateNormal];
    showAppSwitcher.titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
    showAppSwitcher.contentEdgeInsets = UIEdgeInsetsMake(12.0, 22.0, 12.0, 22.0);
    [showAppSwitcher addTarget:self action:@selector(showAppSwitcher:) forControlEvents:UIControlEventTouchUpInside];
    [showAppSwitcher setEnabled:(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone)];
    
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, launch, showAppSwitcher]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 18.0;
    [self.view addSubview:stack];
    
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24.0],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24.0],
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (void)launchHelloTapped:(UIButton *)sender
{
    NXROMLaunchHelloPoC();
}

- (void)showAppSwitcher:(UIButton *)sender
{
    [[NXWindowServer shared] showAppSwitcherExternal];
}

@end

UIViewController *NXMainSlot(void)
{
    NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:@"nyxian.boot.entitlements.mode"];
    PEEnforcementMode enforcement = kPEEnforcementModeEnforcing;
    if([mode isEqualToString:@"permissive"])
    {
        enforcement = kPEEnforcementModePermissive;
    }
    else if ([mode isEqualToString:@"disabled"])
    {
        enforcement = kPEEnforcementModeDisabled;
    }
    
    trust_enforcement_set_mode(enforcement);
    klog_set_obfuscation(NXROMDefaultBool(@"nyxian.boot.log.obfuscated", YES));
    
    [[NXBootstrap shared] bootstrap];
    [[NXBootstrap shared] waitTillDoneNoButton];
    
    BOOL loadKexts = NXROMDefaultBool(@"nyxian.boot.kextLoading", YES);
    [[PEUserspaceManager shared] bootWithKextLoadingEnabled:loadKexts];
    
    return [NXROMRootViewController new];
}

__attribute__((visibility("default")))
void *NXSlotMain(void)
{
    UIViewController *root = NXMainSlot();
    return (__bridge_retained void *)root;
}

__attribute__((visibility("default")))
void *NXSlotCreateWindow(void *scenePtr)
{
    if(scenePtr == NULL)
    {
        return NULL;
    }
    UIWindowScene *scene = (__bridge UIWindowScene *)scenePtr;
    NXWindowServer *window = [NXWindowServer sharedWithWindowScene:scene];
    return window ? (__bridge_retained void *)window : NULL;
}

__attribute__((visibility("default")))
void NXSlotDidAppear(void)
{
    [[NXWindowServer shared] makeKeyAndVisible];
}
