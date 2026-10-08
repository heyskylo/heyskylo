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
#import <LindChain/Phone/NXPMOSEngine.h>

static UIWindow *gSlotWindow;

static UIViewController *NXSlotRootViewController(void)
{
    static UIViewController *controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /* The bootloader flashes this ROM into Library/Boot/Slot/A and resolves
           every path in the manifest relative to that slot root. Mutable
           (reflash-surviving) state lives under Library/RomData/postmarketos/. */
        NSString *slotPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Boot/Slot/A"];
        NSURL *slotURL = [NSURL fileURLWithPath:slotPath isDirectory:YES];
        NSString *dataPath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/RomData"]
            stringByAppendingPathComponent:@"postmarketos"];
        NSURL *dataURL = [NSURL fileURLWithPath:dataPath isDirectory:YES];
        controller = [[NXPostmarketOSViewController alloc] initWithSlotURL:slotURL dataURL:dataURL];
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
    [NXPMOSEngine warmUpJIT];
    [gSlotWindow makeKeyAndVisible];
}