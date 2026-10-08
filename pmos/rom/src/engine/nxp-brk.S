/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * pmos -- the BreakpointJIT trap sequences, implemented natively.
 *
 * Derived from Husk (Leviidev/Husk, GPL-2.0-or-later), src/ios-jit/husk-brk.S.
 *
 * These three routines are the entire request channel to the JIT servicer
 * (StikDebug with the Universal JIT script, or the system StikJIT on iOS 26+).
 * They are reproduced from the documented wire protocol (brk immediate + x16
 * command number) rather than linked from a prebuilt framework, for three
 * reasons:
 *
 *   1. Prebuilt BreakpointJIT frameworks ship as bare binaries with no stated
 *      license. This ROM is GPL-2.0-or-later and cannot take on an unlicensed
 *      dynamic dependency.
 *   2. Embedding ANY framework that carries entitlements into a sideloaded
 *      binary trips AMFI at launch ("has entitlements but is not a main
 *      binary"). With the sequences compiled into the engine library itself,
 *      that whole class of problem disappears.
 *   3. Writing them by hand guarantees the exact encoding.
 *
 * Verified against BreakpointJIT.framework (com.stossy11.BreakpointJIT 1.0):
 *
 *   _BreakGetJITMapping:  mov x16, #0x1 ; brk #0xf00d ; ret
 *   _BreakJITDetach:      mov x16, #0x0 ; brk #0xf00d ; ret
 *   _BreakMarkJITMapping: brk #0x69     ; ret
 *
 * Protocol:
 *   brk #0xf00d dispatches on x16 -- 0 = detach, 1 = prepare region.
 *   Arguments arrive in x0/x1 and the result is written back into x0 before
 *   the servicer resumes us, so the trailing `ret` returns it.
 *   brk #0x69 is serviced by writing the constant 0xE0000069 into x0, which
 *   makes it a cheap "is a servicer actually attached?" probe.
 *
 * If NO servicer is attached, these brk instructions raise a real SIGTRAP.
 * nxp_ios_jit_install_trap_handler() must be installed first so that becomes
 * a NULL return rather than process death.
 */

#if defined(__aarch64__) || defined(__arm64__)

.section __TEXT,__text,regular,pure_instructions

/* void *nxp_brk_get_jit_mapping(void *addr, size_t len);
 * x0 = addr (pass NULL to request a fresh region), x1 = len.
 * Returns the executable region address in x0, or 0 on failure. */
.globl _nxp_brk_get_jit_mapping
.p2align 2
_nxp_brk_get_jit_mapping:
    mov     x16, #1              /* CMD_PREPARE_REGION */
    brk     #0xf00d
    ret

/* void nxp_brk_jit_detach(void); */
.globl _nxp_brk_jit_detach
.p2align 2
_nxp_brk_jit_detach:
    mov     x16, #0              /* CMD_DETACH */
    brk     #0xf00d
    ret

/* uint64_t nxp_brk_probe(void);
 * Returns 0xE0000069 when a servicer is attached and servicing traps. */
.globl _nxp_brk_probe
.p2align 2
_nxp_brk_probe:
    brk     #0x69
    ret

#endif /* aarch64 */