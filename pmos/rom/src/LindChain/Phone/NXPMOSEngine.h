/*
 SPDX-License-Identifier: GPL-2.0-or-later

 NXPMOSEngine — the QEMU/JIT boot driver.

 The engine is UTM's QEMU fork (utmapp/qemu v10.0.12-utm, see engine.lock.tsv)
 built -Dshared_lib=true as libqemu-x86_64-softmmu.dylib, the same in-process
 architecture Husk uses, with TCG JIT enabled by a debugger-granted split-W^X
 region (StikDebug) or the built-in StikJIT MAP_JIT route (iOS 26+). The ROM
 dlopens the dylib at runtime (never links it), so the host builds green with
 or without the engine artifact, and a missing/broken dylib degrades to a clear
 "engine unavailable" state instead of a launch crash.

 Boot flow, exactly one session per process:
   1. NXSlotMain calls +warmUpJIT as soon as the slot host is up, while the
      user can still attach StikDebug (auto-attach) — prewarming claims and
      holds the 256 MiB TCG region up front, because the servicer detaches
      after startup and can never service another request.
   2. On boot, startWithError: runs qemu_init -> nxp_display_init ->
      qemu_main_loop on a background thread. qemu_main_loop blocks until the
      guest powers off; only then does qemu_cleanup run.
   3. While it runs, the display/input bridge methods feed NXSurfaceView:
      lock/unlockFrame snapshots the framebuffer, sendPointer:/sendKey:
      forward virtio-tablet/keyboard input.
*/

#ifndef NXPMOSENGINE_H
#define NXPMOSENGINE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const NXPMOSEngineErrorDomain;

typedef NS_ENUM(NSInteger, NXPMOSEngineErrorCode)
{
    NXPMOSEngineErrorNotBundled = 1,   /* dylib not present in this build */
    NXPMOSEngineErrorBrokenDylib,      /* dylib present but ABI mismatch */
    NXPMOSEngineErrorStart,            /* qemu_init / main loop failed */
};

/* Byte-identical mirror of the engine's NxpFrameInfo (nxp-display.h). The host
   must not include QEMU headers, so this struct is declared here instead. */
typedef struct NXEngineFrame
{
    const void *pixels;   /* 32 bpp, BGRA in memory; valid until unlock */
    int32_t  width;
    int32_t  height;
    int32_t  stride;      /* bytes per row, may exceed width * 4 */
    uint32_t bpp;
    uint64_t generation;  /* bumped when the guest picks a new surface */
    uint64_t sequence;    /* bumped on every gfx_update */
} NXEngineFrame;

typedef NS_ENUM(NSInteger, NXPMOSJITStatus)
{
    NXPMOSJITStatusUnknown   = 0,  /* engine not loaded yet */
    NXPMOSJITStatusNone,           /* no JIT route available */
    NXPMOSJITStatusMAPJIT,         /* built-in StikJIT (iOS 26+) */
    NXPMOSJITStatusTrapJIT,        /* debugger-granted split-W^X region */
};

/* How a QEMU session ended. */
typedef NS_ENUM(NSInteger, NXPMOSEngineEndReason)
{
    NXPMOSEngineEndGuestPowerOff = 0,  /* guest shut itself down */
    NXPMOSEngineEndFailed,             /* qemu_init returned / main loop faulted */
};

@interface NXPMOSEngine : NSObject

@property (nonatomic, readonly, getter=isAvailable) BOOL available;
@property (nonatomic, readonly) NXPMOSJITStatus jitStatus;
@property (nonatomic, readonly, copy) NSString *diskPath;
@property (nonatomic, readonly) NSUInteger memoryMiB;
@property (nonatomic, readonly, nullable) NSURL *slotURL;
@property (nonatomic, readonly, nullable) NSURL *dataURL;

/* Best-effort JIT warm-up performed as soon as the slot host is up. Installs
   the breakpoint trap handler and, when a servicer is attached, claims and
   holds the TCG region while the user is still looking at the download gate.
   Safe to call from any thread; no-ops when the engine dylib is absent. */
+ (void)warmUpJIT;

/* Locates and dlopens libqemu-x86_64-softmmu.dylib from the slot Frameworks
   directory and resolves the host-visible ABI. available == YES only when the
   dylib is present and every symbol the host needs resolved.
   slotURL is the flashed slot root (read-only ROM payloads), dataURL a
   reflash-surviving directory for mutable state (guest image, OVMF vars,
   serial log). */
- (instancetype)initWithDiskPath:(NSString *)diskPath
                       memoryMiB:(NSUInteger)memoryMiB
                        slotURL:(NSURL *)slotURL
                        dataURL:(NSURL *)dataURL;

/* Re-run the JIT grant attempt (prewarm) after the user attached StikDebug or
   enabled built-in StikJIT. Returns the resulting status. */
- (NXPMOSJITStatus)refreshJITStatus;

/* Starts QEMU on the calling thread; blocks until the guest exits. Returns NO
   with a populated error when the engine could not start; otherwise fills
   `reason`. */
- (BOOL)startWithError:(NSError **)error endReason:(nullable NXPMOSEngineEndReason *)reasonOut;

/* Requests an asynchronous shutdown. v1 is a documented no-op: the guest is
   expected to power itself off (Phosh power menu), after which the main loop
   returns and the session tears down cleanly. */
- (void)shutdown;

#pragma mark - Display / input bridge (engine functions)

/* Snapshot the current framebuffer. Returns YES and fills frame when a frame
   exists; frame.pixels is valid only until unlockFrame. May be called from any
   thread (serialised with QEMU's BQL internally). */
- (BOOL)lockFrame:(NXEngineFrame *)frame;
- (void)unlockFrame;

/* Monotonic frame counter — a cheap "guest alive" signal. */
- (uint64_t)displaySequence;

/* Current guest resolution in pixels. */
- (void)guestSizeWidth:(int32_t *)width height:(int32_t *)height;

/* Ask the guest to modeset to a new size. */
- (void)setUISizeWidth:(int32_t)width height:(int32_t)height;

/* Absolute pointer event in guest pixel space. */
- (void)sendPointerAtX:(int32_t)x y:(int32_t)y pressed:(BOOL)pressed;

/* Key event by QKeyCode name ("spc", "ret", "a", …). Returns NO for unknown
   names. */
- (BOOL)sendKey:(NSString *)qcode down:(BOOL)down;

@end

NS_ASSUME_NONNULL_END
#endif /* NXPMOSENGINE_H */