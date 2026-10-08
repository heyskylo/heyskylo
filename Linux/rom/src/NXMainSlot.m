#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <LindChain/WindowServer/NXWindowServer.h>
#import <LindChain/WindowServer/Session/NXLinuxTerminalViewController.h>

UIViewController *NXMainSlot(void)
{
    // The bootloader flashes this ROM into Library/Boot/Slot/A and resolves
    // every path in the manifest (NXRomPaths, NXRomBootLogo) relative to that
    // slot root: kernel/vmlinuz-virt-6.18.35 and initramfs/rish-container.cpio
    // land next to main and the boot logo.
    NSString *slotPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Boot/Slot/A"];
    NSURL *slotURL = [NSURL fileURLWithPath:slotPath isDirectory:YES];
    return [[NXLinuxTerminalViewController alloc] initWithSlotURL:slotURL];
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