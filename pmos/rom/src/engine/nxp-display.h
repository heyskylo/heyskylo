/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * pmos -- the entire surface between the iOS host ROM and QEMU.
 *
 * Derived from Husk (Leviidev/Husk, GPL-2.0-or-later),
 * src/ios-jit/husk-display.h.
 *
 * The host links against libqemu-x86_64-softmmu.dylib (via dlopen) but must
 * never include a QEMU header: QEMU's console.h drags in most of the
 * emulator's internals and cannot be compiled by an Xcode target. Everything
 * the host needs is these few functions, which live inside the dylib and
 * speak plain C.
 */
#ifndef NXP_DISPLAY_H
#define NXP_DISPLAY_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * QEMU compiles most of itself into static libraries with -fvisibility=hidden,
 * so only the handful of symbols it deliberately publishes (qemu_init,
 * qemu_main_loop, bql_lock_impl, the plugin API) end up exported from the
 * dylib. Everything the host must reach is marked with NXP_EXPORT explicitly
 * and listed in system/qemu.symbols.
 */
#define NXP_EXPORT __attribute__((visibility("default")))

typedef struct NxpFrameInfo {
    const void *pixels;
    int32_t  width;
    int32_t  height;
    int32_t  stride;          /* bytes per row -- may exceed width * bpp/8 */
    uint32_t bpp;
    uint64_t generation;      /* bumped by gfx_switch: a new surface */
    uint64_t sequence;        /* bumped by every gfx_update */
} NxpFrameInfo;

/*
 * Register a DisplayChangeListener on console 0. Safe to call once; later
 * calls are ignored. Must be called after qemu_init() and before
 * qemu_main_loop(), from a thread already inside the BQL or one that can take
 * it -- QEMU holds the BQL between qemu_init and qemu_main_loop, so the call
 * itself must not take it.
 */
NXP_EXPORT void nxp_display_init(void);

/*
 * Snapshot the current framebuffer. Returns true and fills `out`; the caller
 * MUST call nxp_display_unlock_frame() afterwards. The pixel pointer stays
 * valid only until the unlock. Safe to call from any thread; internally
 * serialised with the BQL via QEMU's own mutex.
 */
NXP_EXPORT bool     nxp_display_lock_frame(NxpFrameInfo *out);
NXP_EXPORT void     nxp_display_unlock_frame(void);

/* Monotonic draw counter -- cheap "guest alive" signal for the host UI. */
NXP_EXPORT uint64_t nxp_display_sequence(void);

/* Current guest resolution (from the console or the latest surface). */
NXP_EXPORT void nxp_display_guest_size(int32_t *width, int32_t *height);

/* Ask the guest to modeset to a new size (dpy_set_ui_info). */
NXP_EXPORT void nxp_display_set_ui_size(int32_t width, int32_t height);

/* Absolute pointer event in guest pixel space. button_down toggles the left
 * button. Takes the BQL itself; safe from any thread. */
NXP_EXPORT void nxp_display_send_pointer(int32_t x, int32_t y, bool button_down);

/* Key event by QKeyCode *name* ("spc", "ret", "a", ...). Returns false for
 * an unknown name. Takes the BQL itself; safe from any thread. */
NXP_EXPORT bool nxp_display_send_key(const char *qcode_name, bool down);

/* Ask QEMU to redraw (used when the host re-presents after a while). */
NXP_EXPORT void nxp_display_request_update(void);

#ifdef __cplusplus
}
#endif

#endif /* NXP_DISPLAY_H */