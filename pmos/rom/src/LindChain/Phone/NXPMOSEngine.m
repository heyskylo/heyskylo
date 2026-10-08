/*
 SPDX-License-Identifier: GPL-2.0-or-later

 See NXPMOSEngine.h. Runtime dlopen of the engine dylib means the host builds
 and runs green without the engine artifact; the boot driver resolves every
 symbol it needs at startup and reports precisely which stage failed.

 Session lifecycle (all on one background thread, per QEMU's threading rules):
   qemu_init(argv)     -- parses the machine config, creates the console
   nxp_display_init()  -- registers the DisplayChangeListener (needs the console)
   qemu_main_loop()    -- blocks until the guest powers off
   qemu_cleanup()      -- only after the loop has returned
*/

#import "NXPMOSEngine.h"

#include <dlfcn.h>
#include <string.h>

NSString * const NXPMOSEngineErrorDomain = @"org.emexlabs.rom.postmarketos.engine";

static NSString * const NXEngineLibraryName = @"libqemu-x86_64-softmmu.dylib";
static NSUInteger const NXEngineJITRegionMiB = 256;

static NSError *NXPMOSEngineError(NXPMOSEngineErrorCode code, NSString *description)
{
    return [NSError errorWithDomain:NXPMOSEngineErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: description }];
}

#pragma mark - Engine symbol ABI (mirrors the dylib's exported C API)

typedef int  (*NXQemuInitFn)(int argc, char **argv);
typedef void (*NXQemuMainLoopFn)(void);
typedef void (*NXQemuCleanupFn)(void);

typedef struct NXEngineSymbols
{
    void             *handle;
    NXQemuInitFn      qemuInit;
    NXQemuMainLoopFn  qemuMainLoop;
    NXQemuCleanupFn   qemuCleanup;

    void    (*nxpDisplayInit)(void);
    bool    (*nxpLockFrame)(NXEngineFrame *out);
    void    (*nxpUnlockFrame)(void);
    uint64_t(*nxpSequence)(void);
    void    (*nxpGuestSize)(int32_t *width, int32_t *height);
    void    (*nxpSetUISize)(int32_t width, int32_t height);
    void    (*nxpSendPointer)(int32_t x, int32_t y, bool down);
    bool    (*nxpSendKey)(const char *qcode, bool down);
    void    (*nxpRequestUpdate)(void);

    void     (*nxpInstallTrapHandler)(void);
    bool     (*nxpPrewarm)(size_t bytes);
    bool     (*nxpIsAvailable)(void);
    bool     (*nxpMapJITWorks)(void);
    void     (*nxpDetach)(void);
    size_t   (*nxpAvailableMemory)(void);
} NXEngineSymbols;

static NXEngineSymbols gSym = {0};
static BOOL gPrewarmed = NO;

@interface NXPMOSEngine ()
@property (nonatomic, assign) char **sessionArgv;
@property (nonatomic, assign) int sessionArgc;
@end

@implementation NXPMOSEngine

#pragma mark - Loading

+ (void *)engineLibraryHandle
{
    if (gSym.handle != NULL)
    {
        return gSym.handle;
    }
    NSArray<NSString *> *candidates = @[
        ([[NSBundle mainBundle].privateFrameworksPath
            ?: [NSBundle mainBundle].bundlePath
            stringByAppendingPathComponent:NXEngineLibraryName]),
        ([[NSBundle mainBundle].bundlePath
            stringByAppendingPathComponent:[@"Frameworks" stringByAppendingPathComponent:NXEngineLibraryName]]),
        ([[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Boot/Slot/A/Frameworks"]
            stringByAppendingPathComponent:NXEngineLibraryName]),
    ];
    for (NSString *candidate in candidates)
    {
        if (![[NSFileManager defaultManager] fileExistsAtPath:candidate])
        {
            continue;
        }
        void *handle = dlopen(candidate.UTF8String, RTLD_LAZY | RTLD_GLOBAL);
        if (handle == NULL)
        {
            continue;
        }
        gSym.handle = handle;
        return handle;
    }
    return NULL;
}

+ (BOOL)loadEngineSymbols
{
    if (gSym.qemuInit != NULL)
    {
        return YES;
    }
    void *handle = [self engineLibraryHandle];
    if (handle == NULL)
    {
        return NO;
    }
#define NX_SYM(fp, name)                                                      \
    do {                                                                       \
        *(void **)(&fp) = dlsym(handle, name);                                \
        if (fp == NULL) { return NO; }                                         \
    } while (0)
    NX_SYM(gSym.qemuInit,            "qemu_init");
    NX_SYM(gSym.qemuMainLoop,        "qemu_main_loop");
    NX_SYM(gSym.qemuCleanup,         "qemu_cleanup");
    NX_SYM(gSym.nxpDisplayInit,      "nxp_display_init");
    NX_SYM(gSym.nxpLockFrame,        "nxp_display_lock_frame");
    NX_SYM(gSym.nxpUnlockFrame,      "nxp_display_unlock_frame");
    NX_SYM(gSym.nxpSequence,         "nxp_display_sequence");
    NX_SYM(gSym.nxpGuestSize,        "nxp_display_guest_size");
    NX_SYM(gSym.nxpSetUISize,        "nxp_display_set_ui_size");
    NX_SYM(gSym.nxpSendPointer,      "nxp_display_send_pointer");
    NX_SYM(gSym.nxpSendKey,          "nxp_display_send_key");
    NX_SYM(gSym.nxpRequestUpdate,    "nxp_display_request_update");
    NX_SYM(gSym.nxpInstallTrapHandler,"nxp_ios_jit_install_trap_handler");
    NX_SYM(gSym.nxpPrewarm,          "nxp_ios_jit_prewarm");
    NX_SYM(gSym.nxpIsAvailable,      "nxp_ios_jit_is_available");
    NX_SYM(gSym.nxpMapJITWorks,      "nxp_ios_jit_mapjit_works");
    NX_SYM(gSym.nxpDetach,           "nxp_ios_jit_detach");
    NX_SYM(gSym.nxpAvailableMemory,  "nxp_ios_available_memory");
#undef NX_SYM
    return YES;
}

#pragma mark - JIT warm-up

+ (void)warmUpJIT
{
    if (![self loadEngineSymbols])
    {
        return;
    }
    if (gPrewarmed)
    {
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        gSym.nxpInstallTrapHandler();
        gPrewarmed = gSym.nxpPrewarm(NXEngineJITRegionMiB * 1024 * 1024);
    });
}

- (NXPMOSJITStatus)currentJITStatus
{
    if (![NXPMOSEngine loadEngineSymbols])
    {
        return NXPMOSJITStatusUnknown;
    }
    if (gSym.nxpIsAvailable())
    {
        return NXPMOSJITStatusTrapJIT;
    }
    if (gSym.nxpMapJITWorks())
    {
        return NXPMOSJITStatusMAPJIT;
    }
    return NXPMOSJITStatusNone;
}

- (NXPMOSJITStatus)refreshJITStatus
{
    /* Re-claim now that StikDebug may have been attached, or the built-in
       StikJIT toggled on. Detaches nothing; one-shot semantics are enforced by
       the region already being held (prewarm reuses it too). */
    if (![NXPMOSEngine loadEngineSymbols])
    {
        return NXPMOSJITStatusUnknown;
    }
    gSym.nxpInstallTrapHandler();
    if (!gSym.nxpIsAvailable() && !gPrewarmed)
    {
        gPrewarmed = gSym.nxpPrewarm(NXEngineJITRegionMiB * 1024 * 1024);
    }
    return [self currentJITStatus];
}

#pragma mark - Lifecycle

- (instancetype)initWithDiskPath:(NSString *)diskPath
                       memoryMiB:(NSUInteger)memoryMiB
                        slotURL:(NSURL *)slotURL
                        dataURL:(NSURL *)dataURL
{
    self = [super init];
    if (self)
    {
        _diskPath = [diskPath copy];
        _memoryMiB = memoryMiB;
        _slotURL = [slotURL copy];
        _dataURL = [dataURL copy];
        _available = [NXPMOSEngine loadEngineSymbols];
        _jitStatus = [self currentJITStatus];
    }
    return self;
}

- (instancetype)init
{
    return [self initWithDiskPath:@"" memoryMiB:NXDefaultMemoryMiB slotURL:nil dataURL:nil];
}

- (void)dealloc
{
    [self freeSessionArgv];
    if (gSym.handle != NULL)
    {
        /* The handle is process-global (shared with +warmUpJIT); only release
           it if nothing else could still want it. */
        gSym.handle = NULL;
        gSym.qemuInit = NULL;
    }
}

#pragma mark - Guest memory budget

- (NSUInteger)computedMemoryMiB
{
    NSUInteger requested = (self.memoryMiB > 0) ? self.memoryMiB : NXDefaultMemoryMiB;
    if (gSym.nxpAvailableMemory == NULL)
    {
        return requested;
    }
    size_t available = gSym.nxpAvailableMemory();
    NSUInteger availableMiB = (NSUInteger)(available / (1024 * 1024));
    /* 256 MiB TCG region + QEMU's own heap + Metal + a jetsam margin. */
    NSUInteger const overheadMiB = 800;
    NSUInteger budget = (availableMiB > overheadMiB) ? (availableMiB - overheadMiB) : 1024;
    NSUInteger guest = MIN(requested, MAX(1024, budget));
    return guest;
}

#pragma mark - Paths

- (NSString *)ovmfVarsPath
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = self.dataURL.path ? [self.dataURL.path stringByAppendingPathComponent:@"ovmf"] : nil;
    if (dir == nil)
    {
        return nil;
    }
    NSString *path = [dir stringByAppendingPathComponent:@"OVMF_VARS.fd"];
    if (![fm fileExistsAtPath:path])
    {
        NSString *template = self.slotURL.path
            ? [self.slotURL.path stringByAppendingPathComponent:@"firmware/OVMF_VARS.fd"]
            : nil;
        if (template != nil && [fm fileExistsAtPath:template])
        {
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            [fm copyItemAtPath:template toPath:path error:nil];
        }
    }
    return path;
}

- (NSString *)serialLogPath
{
    NSString *dir = self.dataURL.path ? [self.dataURL.path stringByAppendingPathComponent:@"logs"] : nil;
    if (dir == nil)
    {
        return nil;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return [dir stringByAppendingPathComponent:@"serial.log"];
}

#pragma mark - argv

- (void)freeSessionArgv
{
    if (self.sessionArgv != NULL)
    {
        for (int i = 0; i < self.sessionArgc; i++)
        {
            free(self.sessionArgv[i]);
        }
        free(self.sessionArgv);
        self.sessionArgv = NULL;
        self.sessionArgc = 0;
    }
}

- (char **)buildSessionArgvCount:(int *)argc
{
    NSString *ovmfCode = self.slotURL.path
        ? [self.slotURL.path stringByAppendingPathComponent:@"firmware/OVMF_CODE.fd"] : nil;
    NSString *ovmfVars = [self ovmfVarsPath];
    NSString *serialLog = [self serialLogPath];
    NSString *pcBiosDir = self.slotURL.path
        ? [self.slotURL.path stringByAppendingPathComponent:@"pc-bios"] : nil;
    NSUInteger memoryMiB = [self computedMemoryMiB];

    NSArray<NSString *> *args = @[
        @"qemu-system-x86_64",
        @"-machine", @"q35",
        @"-accel", @"tcg,tb-size=256,thread=multi",
        @"-cpu", @"max",
        @"-smp", @"2",
        @"-m", [NSString stringWithFormat:@"%lu", (unsigned long)memoryMiB],
        @"-drive", [NSString stringWithFormat:@"if=pflash,format=raw,unit=0,readonly=on,file=%@",
                            ovmfCode ?: @""],
        @"-drive", [NSString stringWithFormat:@"if=pflash,format=raw,unit=1,file=%@",
                            ovmfVars ?: @""],
        @"-drive", [NSString stringWithFormat:@"file=%@,format=raw,if=none,id=drive0,cache=unsafe",
                            self.diskPath],
        @"-device", @"virtio-blk-pci,drive=drive0,bootindex=0",
        @"-device", @"virtio-gpu-pci",
        @"-device", @"virtio-tablet-pci",
        @"-device", @"virtio-keyboard-pci",
        @"-device", @"virtio-net-pci,netdev=net0",
        @"-netdev", @"user,id=net0",
        @"-serial", serialLog ? [NSString stringWithFormat:@"file:%@", serialLog] : @"none",
        @"-display", @"none",
        @"-monitor", @"none",
        @"-no-reboot",
        pcBiosDir ? [NSString stringWithFormat:@"-L"] : @"",
        pcBiosDir ? pcBiosDir : @"",
    ];

    NSMutableArray<NSString *> *filtered = [NSMutableArray array];
    for (NSString *a in args)
    {
        if (a.length > 0)
        {
            [filtered addObject:a];
        }
    }

    int n = (int)filtered.count;
    char **argv = calloc((size_t)n + 1, sizeof(char *));
    for (int i = 0; i < n; i++)
    {
        argv[i] = strdup(filtered[i].UTF8String);
    }
    argv[n] = NULL;
    *argc = n;
    return argv;
}

#pragma mark - Session

- (BOOL)startWithError:(NSError **)error endReason:(NXPMOSEngineEndReason *)reasonOut
{
    if (![NXPMOSEngine loadEngineSymbols])
    {
        if (error)
        {
            *error = NXPMOSEngineError(NXPMOSEngineErrorNotBundled,
                @"The QEMU JIT engine is not bundled in this ROM (libqemu-x86_64-softmmu.dylib "
                 "is missing from the slot Frameworks directory).");
        }
        return NO;
    }

    if ([self currentJITStatus] == NXPMOSJITStatusNone)
    {
        if (error)
        {
            *error = NXPMOSEngineError(NXPMOSEngineErrorStart,
                @"JIT is not available for this app. Attach StikDebug with the Universal JIT "
                 "script, or enable the built-in StikJIT on iOS 26+, then boot again.");
        }
        return NO;
    }

    gSym.nxpInstallTrapHandler();

    [self freeSessionArgv];
    self.sessionArgv = [self buildSessionArgvCount:&_sessionArgc];

    /* qemu_init takes ownership of argv; it stays alive for the whole session. */
    int rc = gSym.qemuInit(self.sessionArgc, self.sessionArgv);
    if (rc != 0)
    {
        if (error)
        {
            *error = NXPMOSEngineError(NXPMOSEngineErrorStart,
                [NSString stringWithFormat:@"qemu_init returned %d — check the guest disk and "
                                           "firmware are staged correctly.", rc]);
        }
        return NO;
    }
    gSym.nxpDisplayInit();
    gSym.qemuMainLoop();
    gSym.qemuCleanup();
    [self freeSessionArgv];

    if (reasonOut)
    {
        *reasonOut = NXPMOSEngineEndGuestPowerOff;
    }
    return YES;
}

- (void)shutdown
{
    /* v1: no-op. The guest powers itself off (Phosh power menu); the thread
       blocked in qemu_main_loop returns and tears down cleanly on its own. */
}

#pragma mark - Display / input bridge

- (BOOL)lockFrame:(NXEngineFrame *)frame
{
    if (gSym.nxpLockFrame == NULL || frame == NULL)
    {
        return NO;
    }
    return gSym.nxpLockFrame(frame);
}

- (void)unlockFrame
{
    if (gSym.nxpUnlockFrame != NULL)
    {
        gSym.nxpUnlockFrame();
    }
}

- (uint64_t)displaySequence
{
    return gSym.nxpSequence != NULL ? gSym.nxpSequence() : 0;
}

- (void)guestSizeWidth:(int32_t *)width height:(int32_t *)height
{
    if (gSym.nxpGuestSize != NULL)
    {
        gSym.nxpGuestSize(width, height);
    }
}

- (void)setUISizeWidth:(int32_t)width height:(int32_t)height
{
    if (gSym.nxpSetUISize != NULL)
    {
        gSym.nxpSetUISize(width, height);
    }
}

- (void)sendPointerAtX:(int32_t)x y:(int32_t)y pressed:(BOOL)pressed
{
    if (gSym.nxpSendPointer != NULL)
    {
        gSym.nxpSendPointer(x, y, pressed);
    }
}

- (BOOL)sendKey:(NSString *)qcode down:(BOOL)down
{
    if (gSym.nxpSendKey == NULL || qcode.length == 0)
    {
        return NO;
    }
    return gSym.nxpSendKey(qcode.UTF8String, down);
}

@end