/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * pmos -- DisplayChangeListener bridge.  See nxp-display.h.
 *
 * Derived from Husk (Leviidev/Husk, GPL-2.0-or-later),
 * src/ios-jit/husk-display.c. Written fresh (GPL-2.0) rather than adapted from
 * UTM's CocoaSpice, which is Apache-2.0 and therefore incompatible with
 * QEMU's GPLv2.
 */

#include "qemu/osdep.h"
#include "qemu/main-loop.h"
#include "qemu/thread.h"
#include "ui/console.h"
#include "ui/input.h"
#include "qapi/error.h"
#include "qapi/util.h"
#include "qapi/qapi-types-ui.h"

#include "nxp-display.h"

#include <sys/time.h>

/* os/log.h is Apple-only; everywhere else the console print is the whole log. */
#ifdef __APPLE__
#include <os/log.h>
#endif

static double nxp_dpy_now_ms(void)
{
    static double base = 0;
    struct timeval tv;
    gettimeofday(&tv, NULL);
    double t = tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
    if (base == 0) { base = t; }
    return t - base;
}

#ifndef __APPLE__
#define NXP_DLOG(fmt, ...)                                                    \
    do {                                                                       \
        fprintf(stderr, "[%9.2fms][nxp-dpy] " fmt "\n",                        \
                nxp_dpy_now_ms(), ##__VA_ARGS__);                              \
        fflush(stderr);                                                        \
    } while (0)
#else
#define NXP_DLOG(fmt, ...)                                                    \
    do {                                                                       \
        os_log(OS_LOG_DEFAULT, "[nxp-dpy] " fmt, ##__VA_ARGS__);              \
        fprintf(stderr, "[%9.2fms][nxp-dpy] " fmt "\n",                        \
                nxp_dpy_now_ms(), ##__VA_ARGS__);                              \
        fflush(stderr);                                                        \
    } while (0)
#endif

typedef struct NxpDisplayState {
    DisplayChangeListener dcl;
    QemuMutex             lock;

    DisplaySurface *surface;
    uint64_t        generation;
    uint64_t        sequence;
    bool            inited;
} NxpDisplayState;

static NxpDisplayState nxp;

/* ------------------------------------------------------------ DCL callbacks */
/* All of these run on the QEMU main-loop thread with the BQL held. */

static void nxp_dpy_gfx_update(DisplayChangeListener *dcl,
                               int x, int y, int w, int h)
{
    (void)dcl;
    (void)x; (void)y; (void)w; (void)h;
    /*
     * Deliberately not tracking dirty rectangles. The guest framebuffer for a
     * phone-sized surface uploads to a Metal texture in well under a frame, and
     * partial-rect bookkeeping across two threads buys nothing until that stops
     * being true.
     */
    uint64_t seq = qatomic_fetch_inc(&nxp.sequence) + 1;

    /* The first few draws prove the guest is alive; afterwards log sparsely. */
    if (seq <= 5 || (seq % 600) == 0) {
        NXP_DLOG("gfx_update #%llu rect=%dx%d@%d,%d",
                 (unsigned long long)seq, w, h, x, y);
    }
}

static void nxp_dpy_gfx_switch(DisplayChangeListener *dcl,
                               DisplaySurface *new_surface)
{
    (void)dcl;
    qemu_mutex_lock(&nxp.lock);
    nxp.surface = new_surface;
    nxp.generation++;
    uint64_t gen = nxp.generation;
    qemu_mutex_unlock(&nxp.lock);

    if (gen <= 5 || (gen % 600) == 0) {
        NXP_DLOG("gfx_switch gen=%llu surface=%p", gen, (void *)new_surface);
    }
}

static bool nxp_dpy_gfx_check_format(DisplayChangeListener *dcl,
                                     pixman_format_code_t format)
{
    (void)dcl;
    /* 32bpp only: it is what virtio-gpu gives us and what Metal wants. */
    bool ok = (format == PIXMAN_x8r8g8b8 || format == PIXMAN_a8r8g8b8);
    NXP_DLOG("gfx_check_format 0x%x -> %s", (unsigned)format, ok ? "accept" : "reject");
    return ok;
}

static void nxp_dpy_refresh(DisplayChangeListener *dcl)
{
    graphic_hw_update(dcl->con);
}

static const DisplayChangeListenerOps nxp_dcl_ops = {
    .dpy_name             = "nxp",
    .dpy_refresh          = nxp_dpy_refresh,
    .dpy_gfx_update       = nxp_dpy_gfx_update,
    .dpy_gfx_switch       = nxp_dpy_gfx_switch,
    .dpy_gfx_check_format = nxp_dpy_gfx_check_format,
};

/* ------------------------------------------------------------- public API */

NXP_EXPORT void nxp_display_init(void)
{
    if (nxp.inited) {
        NXP_DLOG("init: already initialised, ignoring");
        return;
    }
    NXP_DLOG("init: registering DisplayChangeListener");

    qemu_mutex_init(&nxp.lock);
    nxp.dcl.ops = &nxp_dcl_ops;
    nxp.dcl.con = qemu_console_lookup_by_index(0);

    if (nxp.dcl.con == NULL) {
        /* With -display none QEMU still creates a console for the graphics
         * device, but if the device is missing there is nothing to attach to. */
        NXP_DLOG("init: FATAL -- qemu_console_lookup_by_index(0) returned NULL. "
                 "Check that -device virtio-gpu-pci is on the command line.");
        return;
    }

    register_displaychangelistener(&nxp.dcl);
    nxp.inited = true;
    NXP_DLOG("init: listener registered; QEMU will now drive dpy_refresh");
}

NXP_EXPORT bool nxp_display_lock_frame(NxpFrameInfo *out)
{
    if (!nxp.inited || out == NULL) {
        return false;
    }
    qemu_mutex_lock(&nxp.lock);
    if (nxp.surface == NULL) {
        qemu_mutex_unlock(&nxp.lock);
        return false;
    }
    out->pixels     = surface_data(nxp.surface);
    out->width      = surface_width(nxp.surface);
    out->height     = surface_height(nxp.surface);
    out->stride     = surface_stride(nxp.surface);
    out->bpp        = surface_bits_per_pixel(nxp.surface);
    out->generation = nxp.generation;
    out->sequence   = qatomic_read(&nxp.sequence);

    if (out->pixels == NULL || out->width <= 0 || out->height <= 0) {
        qemu_mutex_unlock(&nxp.lock);
        return false;
    }
    return true; /* caller must unlock */
}

NXP_EXPORT void nxp_display_unlock_frame(void)
{
    if (nxp.inited) {
        qemu_mutex_unlock(&nxp.lock);
    }
}

NXP_EXPORT uint64_t nxp_display_sequence(void)
{
    return nxp.inited ? qatomic_read(&nxp.sequence) : 0;
}

/* ------------------------------------------------------------------- input */

static QemuConsole *nxp_input_console(void)
{
    if (nxp.dcl.con) {
        return nxp.dcl.con;
    }
    return qemu_console_lookup_by_index(0);
}

/* The guest's current resolution, from the console.
 * In GL-less mode this is exactly what a modeset produced. */
static void nxp_input_size(QemuConsole *con, int *w, int *h)
{
    *w = con ? qemu_console_get_width(con, 0) : 0;
    *h = con ? qemu_console_get_height(con, 0) : 0;
    if (*w > 0 && *h > 0) {
        return;
    }
    qemu_mutex_lock(&nxp.lock);
    *w = nxp.surface ? surface_width(nxp.surface) : 0;
    *h = nxp.surface ? surface_height(nxp.surface) : 0;
    qemu_mutex_unlock(&nxp.lock);
}

NXP_EXPORT void nxp_display_guest_size(int32_t *width, int32_t *height)
{
    QemuConsole *con;
    int w = 0, h = 0;
    bool held = bql_locked();

    if (!held) {
        bql_lock();
    }
    con = nxp_input_console();
    nxp_input_size(con, &w, &h);
    if (!held) {
        bql_unlock();
    }
    if (width)  { *width  = w; }
    if (height) { *height = h; }
}

/* Ask the guest to modeset to this size via dpy_set_ui_info(). */
NXP_EXPORT void nxp_display_set_ui_size(int32_t width, int32_t height)
{
    QemuConsole *con;
    QemuUIInfo info;

    if (width <= 0 || height <= 0) {
        return;
    }
    /* Take the lock only if it is not already held: bql_lock() asserts when
     * the lock is already ours (qemu_init holds it until the main loop). */
    bool held = bql_locked();
    if (!held) {
        bql_lock();
    }
    con = nxp_input_console();
    if (con) {
        info = *dpy_get_ui_info(con);
        info.width = width;
        info.height = height;
        dpy_set_ui_info(con, &info, false);
    }
    if (!held) {
        bql_unlock();
    }
    NXP_DLOG("asked the guest for a %dx%d display (console %p)",
             width, height, (void *)con);
}

NXP_EXPORT void nxp_display_send_pointer(int32_t x, int32_t y, bool button_down)
{
    QemuConsole *con;
    int w, h;

    /* qemu_input_* must run under the BQL. */
    bql_lock();
    con = nxp_input_console();
    nxp_input_size(con, &w, &h);

    static uint64_t pointer_events = 0;
    uint64_t ev = ++pointer_events;

    if (con && w > 0 && h > 0) {
        if (x < 0) { x = 0; } else if (x >= w) { x = w - 1; }
        if (y < 0) { y = 0; } else if (y >= h) { y = h - 1; }
        qemu_input_queue_abs(con, INPUT_AXIS_X, x, 0, w);
        qemu_input_queue_abs(con, INPUT_AXIS_Y, y, 0, h);
        qemu_input_queue_btn(con, INPUT_BUTTON_LEFT, button_down);
        qemu_input_event_sync();
        if (ev <= 20 || (ev % 200) == 0) {
            NXP_DLOG("pointer #%llu -> guest (%d,%d) down=%d [surface %dx%d]",
                     (unsigned long long)ev, x, y, button_down ? 1 : 0, w, h);
        }
    } else {
        NXP_DLOG("pointer #%llu DROPPED -- console=%p size=%dx%d",
                 (unsigned long long)ev, (void *)con, w, h);
    }
    bql_unlock();
}

NXP_EXPORT bool nxp_display_send_key(const char *qcode_name, bool down)
{
    QemuConsole *con;

    if (qcode_name == NULL) {
        return false;
    }

    /* Resolved by name through QEMU's own QKeyCode table rather than by
     * passing a raw enum value across the boundary. */
    int qcode = qapi_enum_parse(&QKeyCode_lookup, qcode_name, -1, NULL);
    if (qcode < 0) {
        NXP_DLOG("key '%s' is not a QKeyCode; ignored", qcode_name);
        return false;
    }

    static uint64_t keys = 0;
    uint64_t n = ++keys;

    bql_lock();
    con = nxp_input_console();
    if (con) {
        qemu_input_event_send_key_qcode(con, (QKeyCode)qcode, down);
    }
    bql_unlock();
    if (!con) {
        NXP_DLOG("key '%s' dropped -- no console", qcode_name);
        return false;
    }

    if (n <= 20 || (n % 100) == 0) {
        NXP_DLOG("key #%llu '%s' (qcode %d) down=%d",
                 (unsigned long long)n, qcode_name, qcode, down ? 1 : 0);
    }
    return true;
}

NXP_EXPORT void nxp_display_request_update(void)
{
    if (!nxp.inited) {
        return;
    }
    bql_lock();
    graphic_hw_update(nxp.dcl.con);
    bql_unlock();
}