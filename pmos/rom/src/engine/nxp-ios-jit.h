/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * pmos -- iOS dual-mapped JIT memory for QEMU's TCG.
 *
 * Derived from Husk (Leviidev/Husk, GPL-2.0-or-later),
 * src/ios-jit/husk-ios-jit.h.
 */

#ifndef NXP_IOS_JIT_H
#define NXP_IOS_JIT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* QEMU compiles with -fvisibility=hidden (in the shared-lib branch's link it
   uses an explicit export list); an explicit attribute wins, so everything the
   host ROM needs to reach must be marked. */
#define NXP_EXPORT __attribute__((visibility("default")))

typedef struct NxpDualMapping {
    uint8_t *rw_addr;   /* writable alias  -- emit code here            */
    uint8_t *rx_addr;   /* executable alias -- branch here              */
    size_t   size;
} NxpDualMapping;

/*
 * Install SIGTRAP/SIGBUS handlers that skip an unserviced BreakpointJIT trap
 * (pc += 4, x0 = 0) instead of letting it kill the process. Call once, early,
 * before any JIT allocation. Safe to call when no servicer is attached.
 */
NXP_EXPORT void nxp_ios_jit_install_trap_handler(void);

/*
 * Allocate one dual-mapped region of `bytes`. Returns a mapping whose rw_addr is
 * NULL on failure. `bytes` is rounded up to a 16 KiB page multiple by the
 * caller's contract -- the servicer prepares whole pages.
 */
NxpDualMapping nxp_ios_jit_allocate(size_t bytes);

/*
 * Claim the JIT region now, while the servicer is still attached, and hold it
 * until QEMU asks. Pass the same size QEMU will ask for (tb-size).
 */
NXP_EXPORT bool nxp_ios_jit_prewarm(size_t bytes);

/* Release a mapping obtained from nxp_ios_jit_allocate(). */
void nxp_ios_jit_release(NxpDualMapping *m);

/*
 * Tell the servicer to detach. RX mappings already obtained stay valid and
 * executable; no further allocation is possible afterwards.
 */
NXP_EXPORT void nxp_ios_jit_detach(void);

/* True once a successful allocation has happened -- i.e. JIT is genuinely live. */
NXP_EXPORT bool nxp_ios_jit_is_available(void);

/*
 * Whether this process can execute memory it wrote itself, through a plain
 * MAP_JIT mapping and TCG's own W^X toggle -- the route the built-in StikJIT
 * on iOS 26+ provides. Measured, not inferred.
 */
NXP_EXPORT bool nxp_ios_jit_mapjit_works(void);

/* Log phys_footprint + available-before-jetsam; `tag` labels the call site. */
NXP_EXPORT void nxp_ios_jit_log_footprint(const char *tag);

/* Bytes this process may still allocate before jetsam kills it. */
NXP_EXPORT size_t nxp_ios_available_memory(void);

#ifdef __cplusplus
}
#endif

#endif /* NXP_IOS_JIT_H */