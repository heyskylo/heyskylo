/*
 SPDX-License-Identifier: GPL-2.0-or-later

 NXPMOSEngine — facade around the QEMU/JIT engine library.

 The engine is UTM's QEMU fork (utmapp/qemu v10.0.12-utm, see engine.lock.tsv)
 built -Dshared_lib=true as libqemu-x86_64-softmmu.dylib, the same in-process
 architecture Husk uses, with TCG JIT enabled by an attached debugger's
 split-W^X grant. The ROM dlopens the dylib at runtime instead of linking it,
 so host UI and guest-image pipeline build and are CI-verifiable before the
 engine milestone lands.

 v1 status: the download→verify→decompress→boot host is complete; the dylib
 boot driver (qemu_init / qemu_main_loop glue on a background thread, plus
 the display/touch bridge to NXSurfaceView) is the engine milestone.
*/

#ifndef NXPMOSENGINE_H
#define NXPMOSENGINE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const NXPMOSEngineErrorDomain;

typedef NS_ENUM(NSInteger, NXPMOSEngineErrorCode)
{
    NXPMOSEngineErrorNotBundled = 1,   /* dylib not present in this build */
    NXPMOSEngineErrorBootDriver,       /* dylib present, boot driver pending */
    NXPMOSEngineErrorStart,            /* qemu_init / main loop failed */
};

@interface NXPMOSEngine : NSObject

@property (nonatomic, readonly, getter=isAvailable) BOOL available;
@property (nonatomic, readonly) NSString *diskPath;
@property (nonatomic, readonly) NSUInteger memoryMiB;

/* Locates and dlopens libqemu-x86_64-softmmu.dylib. Candidates are the host
   app frameworks dir, the bundle frameworks dir, and the slot's own
   Frameworks dir. available == YES when any handshake succeeded. */
- (instancetype)initWithDiskPath:(NSString *)diskPath memoryMiB:(NSUInteger)memoryMiB;

/* Starts QEMU on a background thread; blocks until the guest exits (v1: with
   the engine library present this still returns NXPMOSEngineErrorBootDriver
   until the engine milestone wires qemu_init/qemu_main_loop). */
- (BOOL)startWithError:(NSError **)error;

/* Requests an asynchronous shutdown (v1: no-op). */
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
#endif /* NXPMOSENGINE_H */