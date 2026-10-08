/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * pmos -- iOS dual-mapped JIT memory for QEMU's TCG.  See nxp-ios-jit.h.
 *
 * Derived from Husk (Leviidev/Husk, GPL-2.0-or-later),
 * src/ios-jit/husk-ios-jit.c, which was itself derived from AetherPS4-iOS's
 * src/core/ios/ios_jit_allocator.cpp (shadPS4 Emulator Project, GPL-2.0-or-later).
 *
 * ---------------------------------------------------------------------------
 * Why this file exists
 * ---------------------------------------------------------------------------
 * iOS has no hypervisor for third-party apps and its TXM enforcement refuses
 * RWX mmap/mprotect. Executable memory can only be granted by an attached
 * debugger (StikDebug) or, on iOS 26+, by the system JIT switch. This file
 * implements both routes and hands QEMU's tcg/region.c a split-W^X buffer:
 *
 *   Route 1 (trap servicer): BreakGetJITMapping(NULL, size) -> brk #0xf00d,
 *   x16 = 1. StikDebug catches the trap, allocates an R-X region inside us
 *   with debugserver `_M<size>,rx`, walks every 16 KiB page with a one-byte
 *   write through the debugger (`M<addr>,1:69`), and stuffs the address back
 *   into x0. We then make our own writable alias of the same physical pages
 *   with vm_remap. QEMU emits code through RW, executes through RX, and
 *   tcg/region.c understands exactly this shape via tcg_splitwx_diff.
 *
 *   Route 2 (MAP_JIT): with CS_DEBUGGED set (StikJIT on iOS 26+), the kernel
 *   honours a plain MAP_JIT mapping toggled via the APRR comm page
 *   (tcg-apple-jit.h). nxp_ios_jit_mapjit_works() measures whether this
 *   process has it; when yes, TCG's own MAP_JIT path handles the buffer.
 *
 * ---------------------------------------------------------------------------
 * The one-shot rule
 * ---------------------------------------------------------------------------
 * After setup the app calls nxp_ios_jit_detach() and the servicer goes away.
 * From then on a further trap is NOT serviced -- and an unserviced `brk` is a
 * fatal SIGTRAP, not a failed call. So: allocate ONCE, up front, at a size
 * that is provably sufficient for the whole session. QEMU is a natural fit:
 * TCG sizes its translation buffer once at init from `-accel tcg,tb-size=N`
 * and flushes rather than grows when it fills.
 */

#include "nxp-ios-jit.h"

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

#if defined(__APPLE__) && TARGET_OS_IPHONE

#include <errno.h>
#include <mach/mach.h>
#include <mach/vm_map.h>        /* vm_remap/vm_protect: mach_vm.h is absent from the iOS SDK */
#include <os/log.h>
#include <os/proc.h>
#include <setjmp.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <mach/task.h>
#include <mach/task_info.h>
#include <libkern/OSCacheControl.h>
#include <sys/ucontext.h>   /* not <ucontext.h>: that one #errors without _XOPEN_SOURCE */
#include <unistd.h>
#include <fcntl.h>

/*
 * Provide pipe2 for iOS systems where libc does not export it. Compiled into
 * the dylib, so it also satisfies any QEMU-internal pipe2 references.
 */
__attribute__((visibility("default")))
int pipe2(int fds[2], int flags)
{
    if (!fds) {
        errno = EFAULT;
        return -1;
    }
    if (pipe(fds) < 0) {
        return -1;
    }
    if (flags & O_CLOEXEC) {
        if (fcntl(fds[0], F_SETFD, FD_CLOEXEC) < 0 ||
            fcntl(fds[1], F_SETFD, FD_CLOEXEC) < 0) {
            int err = errno;
            close(fds[0]);
            close(fds[1]);
            errno = err;
            return -1;
        }
    }
    if (flags & O_NONBLOCK) {
        int f0 = fcntl(fds[0], F_GETFL);
        int f1 = fcntl(fds[1], F_GETFL);
        if (f0 < 0 || f1 < 0 ||
            fcntl(fds[0], F_SETFL, f0 | O_NONBLOCK) < 0 ||
            fcntl(fds[1], F_SETFL, f1 | O_NONBLOCK) < 0) {
            int err = errno;
            close(fds[0]);
            close(fds[1]);
            errno = err;
            return -1;
        }
    }
    return 0;
}

/* TCG's own W^X toggle. pthread_jit_write_protect_np() is marked unavailable in
 * the iOS SDK -- the symbol exists but the header refuses it -- so QEMU pokes
 * the APRR registers through the comm page instead. This file is compiled
 * inside QEMU's tcg/ directory, so the same header is the right one to use. */
#include "tcg/tcg-apple-jit.h"

/* Maximum verbosity by default: this path is nearly impossible to debug after
 * the fact on device, and every line here is printed at most a handful of times
 * per session. Goes to os_log (visible in Console.app) and stderr both. */
static double nxp_now_ms(void)
{
    static double base = 0;
    struct timeval tv;
    gettimeofday(&tv, NULL);
    double t = tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
    if (base == 0) { base = t; }
    return t - base;
}

#define NXP_LOG(fmt, ...)                                                     \
    do {                                                                       \
        os_log(OS_LOG_DEFAULT, "[nxp-jit] " fmt, ##__VA_ARGS__);              \
        fprintf(stderr, "[%9.2fms][nxp-jit] " fmt "\n",                        \
                nxp_now_ms(), ##__VA_ARGS__);                                  \
        fflush(stderr);                                                        \
    } while (0)

/* ------------------------------------------------------------------ symbols */
/*
 * The trap sequences live in nxp-brk.S, compiled straight into this binary
 * (the engine dylib). We deliberately do NOT link or dlopen a prebuilt
 * BreakpointJIT.framework: it has no stated license, and any embedded
 * framework carrying entitlements is rejected by AMFI at launch.
 */
extern void    *nxp_brk_get_jit_mapping(void *addr, size_t len);
extern void     nxp_brk_jit_detach(void);
extern uint64_t nxp_brk_probe(void);

/*
 * StikDebug answers brk #0x69 by writing a constant into x0. Two encodings are
 * seen in the wild:
 *
 *   0xE0000069  -- the value as written in the script
 *   0x690000E0  -- that value byte-reversed, which is what universal.js actually
 *                  produces: it sends the gdb-remote packet `P0=E0000069`, but P
 *                  takes the register in TARGET byte order, and ARM64 is little
 *                  endian. It also supplies only 4 bytes for an 8-byte register,
 *                  so the upper half keeps whatever poison was there.
 *
 * Matching on an exact value is therefore the wrong test. What actually
 * distinguishes "serviced" from "not serviced" is far simpler: when no
 * servicer is present, our own SIGTRAP handler steps over the brk and sets x0
 * to exactly 0. So any non-zero answer means something serviced the trap.
 */
#define NXP_PROBE_MAGIC    0xE0000069ull
#define NXP_PROBE_MAGIC_LE 0x690000E0ull

static atomic_bool           g_jit_available;
static atomic_uint_least64_t g_alloc_counter;

/* ------------------------------------------------------- unserviced-trap guard */
/*
 * Set for exactly the duration of the BreakGetJITMapping call. If no servicer
 * is there to service the brk, the trap is a real SIGTRAP that would otherwise
 * kill the process outright -- there is no "call returned an error" to recover
 * from. The handler below turns that into a NULL return, which the allocation
 * path already handles.
 */
static _Thread_local bool g_expecting_jit_trap;

static struct sigaction g_prev_sigtrap;
static struct sigaction g_prev_sigbus;

static void nxp_trap_handler(int sig, siginfo_t *info, void *ctx)
{
    (void)info;
    if (g_expecting_jit_trap && ctx != NULL) {
        ucontext_t *uc = (ucontext_t *)ctx;
        /* Step over the brk and report failure in x0, exactly as the
         * serviced path would have written a result there. */
        uc->uc_mcontext->__ss.__pc += 4;
        uc->uc_mcontext->__ss.__x[0] = 0;
        return;
    }

    /* Not ours: restore and re-raise so a genuine breakpoint or bus error is
     * not silently swallowed. */
    struct sigaction *prev = (sig == SIGTRAP) ? &g_prev_sigtrap : &g_prev_sigbus;
    sigaction(sig, prev, NULL);
    raise(sig);
}

NXP_EXPORT void nxp_ios_jit_install_trap_handler(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_flags = SA_SIGINFO;
    sa.sa_sigaction = nxp_trap_handler;
    sigemptyset(&sa.sa_mask);

    if (sigaction(SIGTRAP, &sa, &g_prev_sigtrap) != 0) {
        NXP_LOG("sigaction(SIGTRAP) failed: %s", strerror(errno));
    }
    if (sigaction(SIGBUS, &sa, &g_prev_sigbus) != 0) {
        NXP_LOG("sigaction(SIGBUS) failed: %s", strerror(errno));
    }
    NXP_LOG("trap guard installed (SIGTRAP, SIGBUS)");
}

/* ---------------------------------------------------------------- footprint */
/*
 * phys_footprint is the figure jetsam judges us on, so it is the one worth
 * logging around every large allocation. An iOS app with the
 * increased-memory-limit entitlement still dies silently when this crosses the
 * device's cap, and a silent kill with no crash log is otherwise very hard to
 * tell apart from any other sudden death.
 */
NXP_EXPORT void nxp_ios_jit_log_footprint(const char *tag)
{
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count)
        != KERN_SUCCESS) {
        NXP_LOG("footprint[%s]: task_info failed", tag ? tag : "");
        return;
    }
    size_t avail = os_proc_available_memory();

    NXP_LOG("footprint[%s]: phys=%.1f MiB  resident=%.1f MiB  "
            "available-before-jetsam=%.1f MiB",
            tag ? tag : "",
            info.phys_footprint / (1024.0 * 1024.0),
            info.resident_size  / (1024.0 * 1024.0),
            avail / (1024.0 * 1024.0));
}

NXP_EXPORT size_t nxp_ios_available_memory(void)
{
    return os_proc_available_memory();
}

/* ---------------------------------------------------------------- self-test */
/*
 * The decisive check. A servicer can hand back an address, and vm_remap can
 * succeed, while the pages were never actually prepared -- `_M,rx` allocating
 * without the per-page walk looks identical from here. In that case nothing
 * goes wrong until TCG branches into generated code, and the app dies somewhere
 * deep in the emulator with no useful context.
 *
 * So: write a two-instruction function through the RW alias, then CALL it
 * through the RX alias. If JIT works at all, this returns 42.
 */
static bool nxp_jit_selftest(const NxpDualMapping *m)
{
    /* movz w0, #42  ;  ret */
    static const uint32_t kCode[2] = { 0x52800540u, 0xD65F03C0u };

    if (m->rw_addr == NULL || m->rx_addr == NULL) {
        return false;
    }

    NXP_LOG("selftest: writing %zu bytes through RW alias %p", sizeof(kCode),
            (void *)m->rw_addr);
    memcpy(m->rw_addr, kCode, sizeof(kCode));

    /* Flush the write through to the RX view before executing it. */
    sys_icache_invalidate(m->rx_addr, sizeof(kCode));

    /* Read back through RX to confirm the two aliases really share pages. */
    uint32_t readback[2];
    memcpy(readback, m->rx_addr, sizeof(readback));
    if (readback[0] != kCode[0] || readback[1] != kCode[1]) {
        NXP_LOG("selftest: FAIL -- RX alias does not reflect RW writes. The two "
                "mappings are not backed by the same pages.");
        return false;
    }

    int (*fn)(void) = (int (*)(void))(void *)m->rx_addr;
    int result = fn();
    if (result != 42) {
        NXP_LOG("selftest: FAIL -- generated code ran but returned %d", result);
        return false;
    }
    NXP_LOG("selftest: PASS -- executed generated code from the RX alias. JIT "
            "is genuinely live.");
    return true;
}

/* ------------------------------------------------------------- allocation */

/*
 * Take the JIT region early, before anything slow happens.
 *
 * A servicer (StikDebug) does not stay attached indefinitely. A first run
 * downloads ~1.5 GB of guest image before QEMU starts, and by the time
 * qemu_init() reaches alloc_code_gen_buffer the debugger may have let go.
 * So the region is claimed at boot time, while the attachment is fresh, and
 * held until QEMU asks for it.
 */
static NxpDualMapping nxp_ios_jit_allocate_real(size_t bytes);

static NxpDualMapping nxp_prewarmed;
static bool nxp_prewarm_done;

NXP_EXPORT bool nxp_ios_jit_prewarm(size_t bytes)
{
    if (nxp_prewarm_done) {
        return nxp_prewarmed.rw_addr != NULL;
    }
    nxp_prewarm_done = true;
    nxp_prewarmed = nxp_ios_jit_allocate_real(bytes);
    fprintf(stderr, "[nxp-jit] prewarm %s: %zu bytes\n",
            nxp_prewarmed.rw_addr ? "OK" : "FAILED", bytes);
    return nxp_prewarmed.rw_addr != NULL;
}

NxpDualMapping nxp_ios_jit_allocate(size_t bytes)
{
    /*
     * Hand back the prewarmed region when it is big enough. QEMU asks for
     * exactly tb-size, which is what prewarm was given, so this is the normal
     * path -- the fallback below only runs if prewarm never happened.
     */
    if (nxp_prewarmed.rw_addr && nxp_prewarmed.size >= bytes) {
        fprintf(stderr, "[nxp-jit] using the prewarmed region (%zu bytes)\n",
                nxp_prewarmed.size);
        return nxp_prewarmed;
    }
    /*
     * No second trap after a prewarm already went unanswered. Inside
     * qemu_init there is even less chance a servicer is listening, and one
     * that is attached but not answering keeps the whole process stopped on
     * the brk, so the app freezes. Failing here lets region.c fall back to
     * MAP_JIT, or lets qemu_init report the error.
     */
    if (nxp_prewarm_done) {
        fprintf(stderr, "[nxp-jit] prewarm failed earlier; not trapping again\n");
        NxpDualMapping none = { NULL, NULL, 0 };
        return none;
    }
    return nxp_ios_jit_allocate_real(bytes);
}

static NxpDualMapping nxp_ios_jit_allocate_real(size_t bytes)
{
    NxpDualMapping region = { NULL, NULL, 0 };
    uint64_t n = atomic_fetch_add(&g_alloc_counter, 1) + 1;

    /* Cheap attach probe: brk #0x69 is answered with a constant when a
     * servicer is live, and swallowed by our trap handler as 0 when it is not.
     * Doing this first turns "no servicer" into a clean diagnostic instead of
     * three slow retries of the real request. */
    g_expecting_jit_trap = true;
    uint64_t probe = nxp_brk_probe();
    g_expecting_jit_trap = false;
    if (probe == 0) {
        NXP_LOG("#%llu: no trap servicer responding (probe returned 0). Cannot "
                "allocate %zu bytes.",
                (unsigned long long)n, bytes);
        return region;
    }

    uint32_t probe_lo = (uint32_t)probe;
    if (probe_lo == (uint32_t)NXP_PROBE_MAGIC ||
        probe_lo == (uint32_t)NXP_PROBE_MAGIC_LE) {
        NXP_LOG("#%llu: servicer attach probe OK (0x%llx)",
                (unsigned long long)n, (unsigned long long)probe);
    } else {
        /* Serviced, but by something that answers differently. Proceed -- the
         * allocation itself is the real test. */
        NXP_LOG("#%llu: trap was serviced but the answer is unrecognised (0x%llx). "
                "Continuing anyway.",
                (unsigned long long)n, (unsigned long long)probe);
    }

    /*
     * Ask for a FRESH region (x0 == 0) so the servicer allocates it with
     * debugserver `_M<size>,rx` and then walks every 16 KiB page with
     * `M<addr>,1:69`. Requesting a fresh region is the only branch that gets
     * those pages prepared.
     */
    enum { kMaxAttempts = 3 };
    void *rx = NULL;
    for (int attempt = 1; attempt <= kMaxAttempts; attempt++) {
        NXP_LOG("#%llu: requesting execute-capable region, size=%zu (%.1f MiB), "
                "attempt %d/%d",
                (unsigned long long)n, bytes, (double)bytes / (1024.0 * 1024.0),
                attempt, kMaxAttempts);

        g_expecting_jit_trap = true;
        rx = nxp_brk_get_jit_mapping(NULL, bytes);
        g_expecting_jit_trap = false;

        NXP_LOG("#%llu: BreakGetJITMapping returned %p", (unsigned long long)n, rx);
        if (rx != NULL) {
            break;
        }
        if (attempt < kMaxAttempts) {
            usleep(50 * 1000);
        }
    }

    if (rx == NULL) {
        NXP_LOG("#%llu: FAILED after %d attempts. Attach StikDebug with the "
                "Universal JIT script (or enable the built-in StikJIT on iOS 26+) "
                "before booting the guest.",
                (unsigned long long)n, kMaxAttempts);
        return region;
    }

    /* Writable alias of the same physical pages. Purely local -- no debugger
     * involvement, and therefore still available after detach. */
    vm_address_t rw = 0;
    vm_prot_t cur_prot = VM_PROT_NONE, max_prot = VM_PROT_NONE;
    kern_return_t kr = vm_remap(mach_task_self(), &rw, (vm_size_t)bytes,
                                /*mask=*/0, VM_FLAGS_ANYWHERE,
                                mach_task_self(), (vm_address_t)rx,
                                /*copy=*/FALSE, &cur_prot, &max_prot,
                                VM_INHERIT_NONE);
    if (kr != KERN_SUCCESS) {
        NXP_LOG("#%llu: vm_remap failed for rx=%p size=%zu: %d (%s)",
                (unsigned long long)n, rx, bytes, (int)kr, mach_error_string(kr));
        return region;
    }

    kr = vm_protect(mach_task_self(), rw, (vm_size_t)bytes, /*set_maximum=*/FALSE,
                    VM_PROT_READ | VM_PROT_WRITE);
    if (kr != KERN_SUCCESS) {
        NXP_LOG("#%llu: vm_protect(RW) failed for rw=%p size=%zu: %d (%s)",
                (unsigned long long)n, (void *)rw, bytes, (int)kr,
                mach_error_string(kr));
        vm_deallocate(mach_task_self(), rw, (vm_size_t)bytes);
        return region;
    }

    region.rw_addr = (uint8_t *)rw;
    region.rx_addr = (uint8_t *)rx;
    region.size    = bytes;
    atomic_store(&g_jit_available, true);

    NXP_LOG("#%llu: dual mapping established: rw=%p rx=%p size=%zu diff=%+lld",
            (unsigned long long)n, (void *)region.rw_addr, (void *)region.rx_addr,
            region.size, (long long)(region.rx_addr - region.rw_addr));
    nxp_ios_jit_log_footprint("after-jit-alloc");

    if (!nxp_jit_selftest(&region)) {
        NXP_LOG("#%llu: SELFTEST FAILED -- the region is not usable as JIT "
                "memory. Refusing to hand it to TCG.",
                (unsigned long long)n);
        nxp_ios_jit_release(&region);
        return region;
    }

    return region;
}

void nxp_ios_jit_release(NxpDualMapping *m)
{
    if (m == NULL) {
        return;
    }
    if (m->rw_addr != NULL) {
        vm_deallocate(mach_task_self(), (vm_address_t)m->rw_addr, (vm_size_t)m->size);
        m->rw_addr = NULL;
    }
    if (m->rx_addr != NULL) {
        vm_deallocate(mach_task_self(), (vm_address_t)m->rx_addr, (vm_size_t)m->size);
        m->rx_addr = NULL;
    }
    m->size = 0;
}

NXP_EXPORT void nxp_ios_jit_detach(void)
{
    NXP_LOG("detaching servicer; RX mappings persist after this");
    g_expecting_jit_trap = true;
    nxp_brk_jit_detach();
    g_expecting_jit_trap = false;
    NXP_LOG("servicer detached");
}

NXP_EXPORT bool nxp_ios_jit_is_available(void)
{
    return atomic_load(&g_jit_available);
}

/* ------------------------------------------------------------- MAP_JIT probe */
/*
 * Ask the kernel what it actually granted, before branching into it.
 * The signal guard below catches a fault, but not every refusal arrives as a
 * signal: a device that enforces TXM can answer an attempt to execute
 * unblessed memory by killing the process outright. So the dangerous
 * instruction is only reached once the kernel has said the page carries
 * execute permission.
 */
static bool nxp_page_is_executable(void *p)
{
    vm_address_t addr = (vm_address_t)p;
    vm_size_t size = 0;
    natural_t depth = 0;
    vm_region_submap_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;

    kern_return_t kr = vm_region_recurse_64(mach_task_self(), &addr, &size, &depth,
                                            (vm_region_recurse_info_t)&info, &count);
    if (kr != KERN_SUCCESS) {
        NXP_LOG("MAP_JIT probe: vm_region_recurse_64 failed: %s", mach_error_string(kr));
        return false;
    }
    NXP_LOG("MAP_JIT probe: kernel granted protection 0x%x (execute %s)",
            (unsigned)info.protection,
            (info.protection & VM_PROT_EXECUTE) ? "yes" : "NO");
    return (info.protection & VM_PROT_EXECUTE) != 0;
}

static sigjmp_buf g_probe_jump;
static volatile sig_atomic_t g_probe_running;

static void nxp_probe_handler(int sig)
{
    if (g_probe_running) {
        siglongjmp(g_probe_jump, 1);
    }
    /* Not ours -- a fault on another thread inside the probe's brief window. */
    signal(sig, SIG_DFL);
    raise(sig);
}

/*
 * Can this process execute memory it wrote itself?
 *
 * This is the route the built-in StikJIT on iOS 26+ provides: the toggle sets
 * CS_DEBUGGED, and the kernel then honours a plain MAP_JIT mapping toggled
 * with jit_write_protect(). Whether that is available depends on the device,
 * the iOS version and which tool enabled JIT -- so this measures it.
 */
NXP_EXPORT bool nxp_ios_jit_mapjit_works(void)
{
    static atomic_int cached;   /* 0 unknown, 1 yes, -1 no */
    int known = atomic_load(&cached);
    if (known != 0) {
        return known > 0;
    }

    /* movz w0, #0x1234  ;  ret */
    static const uint32_t kCode[2] = { 0x52824680u, 0xD65F03C0u };
    const size_t len = 16 * 1024;   /* one iOS page */
    bool ok = false;

    void *p = mmap(NULL, len, PROT_READ | PROT_WRITE | PROT_EXEC,
                   MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (p == MAP_FAILED) {
        NXP_LOG("MAP_JIT probe: mmap refused (%s) -- a trap servicer is the "
                "only route on this device", strerror(errno));
        atomic_store(&cached, -1);
        return false;
    }

    if (!nxp_page_is_executable(p)) {
        NXP_LOG("MAP_JIT probe: the mapping came back without execute permission");
        munmap(p, len);
        atomic_store(&cached, -1);
        return false;
    }

    struct sigaction sa, prev_bus, prev_segv, prev_ill;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = nxp_probe_handler;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGBUS, &sa, &prev_bus);
    sigaction(SIGSEGV, &sa, &prev_segv);
    sigaction(SIGILL, &sa, &prev_ill);

    g_probe_running = 1;
    if (sigsetjmp(g_probe_jump, 1) == 0) {
        /* On a device with APRR the page is write-protected until asked
         * otherwise; on one without, it is plain RWX and these are no-ops. */
        if (jit_write_protect_supported()) { jit_write_protect(0); }
        memcpy(p, kCode, sizeof(kCode));
        if (jit_write_protect_supported()) { jit_write_protect(1); }
        sys_icache_invalidate(p, sizeof(kCode));

        int (*fn)(void) = (int (*)(void))p;
        ok = (fn() == 0x1234);
    } else {
        NXP_LOG("MAP_JIT probe: faulted while executing the page");
    }
    g_probe_running = 0;

    sigaction(SIGBUS, &prev_bus, NULL);
    sigaction(SIGSEGV, &prev_segv, NULL);
    sigaction(SIGILL, &prev_ill, NULL);
    munmap(p, len);

    NXP_LOG("MAP_JIT probe: %s", ok
            ? "PASS -- MAP_JIT is executable in this process"
            : "FAIL -- MAP_JIT memory is not executable here");
    atomic_store(&cached, ok ? 1 : -1);
    return ok;
}

#else /* !iOS: keep the symbols so host builds and tests link */

NXP_EXPORT void nxp_ios_jit_install_trap_handler(void) {}
static NxpDualMapping nxp_ios_jit_allocate_real(size_t bytes)
{
    (void)bytes;
    NxpDualMapping m = { NULL, NULL, 0 };
    return m;
}
NxpDualMapping nxp_ios_jit_allocate(size_t bytes)
{
    return nxp_ios_jit_allocate_real(bytes);
}
NXP_EXPORT bool nxp_ios_jit_prewarm(size_t bytes) { (void)bytes; return false; }
void nxp_ios_jit_release(NxpDualMapping *m) { (void)m; }
NXP_EXPORT void nxp_ios_jit_detach(void) {}
NXP_EXPORT bool nxp_ios_jit_is_available(void) { return false; }
NXP_EXPORT bool nxp_ios_jit_mapjit_works(void) { return false; }
NXP_EXPORT void nxp_ios_jit_log_footprint(const char *tag) { (void)tag; }
NXP_EXPORT size_t nxp_ios_available_memory(void) { return 0; }

#endif