/*
 SPDX-License-Identifier: GPL-2.0-or-later

 Nyxian slot ABI glue. The bootloader dlopens `main` and exports the symbols
 below; the floor is NXSlotMain. This ROM presents a single window hosting
 NXPostmarketOSViewController — no window-server chrome, matching the
 full-screen spec.
*/

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <LindChain/Phone/NXPostmarketOSViewController.h>

static UIWindow *gSlotWindow;

static UIViewController *NXSlotRootViewController(void)
{
    static UIViewController *controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // The bootloader flashes this ROM into Library/Boot/Slot/A and
        // resolves every path in the manifest relative to that slot root.
        // The guest image is downloaded at runtime into <slot>/guest/.
        NSString *slotPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Boot/Slot/A"];
        NSURL *slotURL = [NSURL fileURLWithPath:slotPath isDirectory:YES];
        controller = [[NXPostmarketOSViewController alloc] initWithSlotURL:slotURL];
    });
    return controller;
}

__attribute__((visibility("default")))
void *NXSlotMain(void)
{
    UIViewController *root = NXSlotRootViewController();
    return (__bridge_retained void *)root;
}

__attribute__((visibility("default")))
void *NXSlotCreateWindow(void *scenePtr)
{
    if (scenePtr == NULL)
    {
        return NULL;
    }
    UIWindowScene *scene = (__bridge UIWindowScene *)scenePtr;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    window.rootViewController = NXSlotRootViewController();

    gSlotWindow = window;

    return (__bridge_retained void *)window;
}

__attribute__((visibility("default")))
void NXSlotDidAppear(void)
{
    [gSlotWindow makeKeyAndVisible];
}