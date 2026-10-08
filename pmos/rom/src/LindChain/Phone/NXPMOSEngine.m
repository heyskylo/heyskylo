/*
 SPDX-License-Identifier: GPL-2.0-or-later

 See NXPMOSEngine.h. Runtime dlopen of the engine dylib lets us ship and CI
 everything except the engine itself: the ROM never links the dylib, so the
 host image builds green with or without it, and the engine milestone only
 has to drop the right artifact into the slot's Frameworks directory.
*/

#import "NXPMOSEngine.h"

#include <dlfcn.h>

NSString * const NXPMOSEngineErrorDomain = @"org.emexlabs.rom.postmarketos.engine";

static NSString * const NXEngineLibraryName = @"libqemu-x86_64-softmmu.dylib";

static NSError *NXPMOSEngineError(NXPMOSEngineErrorCode code, NSString *description)
{
    return [NSError errorWithDomain:NXPMOSEngineErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: description }];
}

/* The future boot-driver ABI this facade will call once the engine milestone
   lands (symbols exported by the UTM-fork dylib build):
     int qemu_probe(const char *machine)        // handshake, returns 0
     int qemu_init_config(const char *json)     // machine args as JSON
     void qemu_main_loop(void)                  // blocks until guest exits
     void qemu_cleanup(void)
   The JSON machine config embeds the disk path ({disk}), memory, CPUs, TCG
   settings (tb-size for one-shot JIT setup), and the display/touch bridge.
*/

@interface NXPMOSEngine ()
@property (nonatomic, assign) void *dylibHandle;
@end

@implementation NXPMOSEngine

- (instancetype)initWithDiskPath:(NSString *)diskPath memoryMiB:(NSUInteger)memoryMiB
{
    self = [super init];
    if (self)
    {
        _diskPath = diskPath;
        _memoryMiB = memoryMiB;
        _dylibHandle = [NXPMOSEngine locateEngineLibrary];
        _available = (_dylibHandle != NULL);
    }
    return self;
}

+ (void *)locateEngineLibrary
{
    NSArray<NSString *> *candidates = @[
        ([NSBundle mainBundle].privateFrameworksPath
            ? [[NSBundle mainBundle].privateFrameworksPath stringByAppendingPathComponent:NXEngineLibraryName]
            : @""),
        ([[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:[@"Frameworks" stringByAppendingPathComponent:NXEngineLibraryName]]),
        ([[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Boot/Slot/A/Frameworks"] stringByAppendingPathComponent:NXEngineLibraryName]),
    ];

    for (NSString *candidate in candidates)
    {
        if (candidate.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:candidate])
        {
            continue;
        }
        void *handle = dlopen(candidate.UTF8String, RTLD_LAZY | RTLD_GLOBAL);
        if (handle != NULL)
        {
            return handle;
        }
    }
    return NULL;
}

- (BOOL)startWithError:(NSError **)error
{
    if (!self.available)
    {
        if (error)
        {
            *error = NXPMOSEngineError(NXPMOSEngineErrorNotBundled,
                @"The QEMU JIT engine is not bundled in this ROM build yet (engine milestone). "
                 "The host, downloader, verifier, and decoder are in place; "
                 "libqemu-x86_64-softmmu.dylib still needs to be built from "
                 "utmapp/qemu v10.0.12-utm and dropped into the slot Frameworks directory.");
        }
        return NO;
    }

    /* Engine dylib present but the boot driver (qemu_init_config +
       qemu_main_loop glue) is the engine milestone. */
    if (error)
    {
        *error = NXPMOSEngineError(NXPMOSEngineErrorBootDriver,
            @"Engine library found, but the boot driver is not wired yet (engine milestone).");
    }
    return NO;
}

- (void)shutdown
{
}

- (void)dealloc
{
    if (_dylibHandle != NULL)
    {
        dlclose(_dylibHandle);
        _dylibHandle = NULL;
    }
}

@end