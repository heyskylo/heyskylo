#!/bin/sh
# pmos engine dependency pins.
#
# Mirror of Husk's scripts/sources.sh (Leviidev/Husk, GPL-2.0-or-later). The
# versions deliberately match UTM's patches/sources where they overlap, because
# those exact versions are known to cross-compile for arm64-apple-ios. pmos
# needs the subset required for a headless system-mode x86_64 QEMU: no spice,
# no gstreamer, no virglrenderer, no MoltenVK, no usb, no tpm.

# QEMU: UTM's fork release. Chosen over upstream v11.1.1 because this tarball
# already carries --enable-shared-lib (QEMU built as a dylib rather than an
# executable), which upstream does not have and which pmos requires -- iOS apps
# cannot spawn processes, so QEMU must live in-process. Its TCG is stock
# upstream: UTM's separate qemu-10.0.12-utm.patch (vendored in patches/) does
# not touch tcg/. The iOS split-W^X hooks we add live in vas tcg/region.c
# patch (patches/nxp-qemu-ios-jit.patch), applied by integrate-engine.sh.
QEMU_SRC="https://github.com/utmapp/qemu/releases/download/v10.0.12-utm/qemu-10.0.12-utm.tar.xz"

# Hard requirements for system-mode QEMU.
FFI_SRC="https://github.com/libffi/libffi/releases/download/v3.5.0/libffi-3.5.0.tar.gz"
ICONV_SRC="https://ftp.gnu.org/gnu/libiconv/libiconv-1.16.tar.gz"
GETTEXT_SRC="https://ftp.gnu.org/gnu/gettext/gettext-0.22.5.tar.gz"
GLIB_SRC="https://download.gnome.org/sources/glib/2.83/glib-2.83.0.tar.xz"
PIXMAN_SRC="https://www.cairographics.org/releases/pixman-0.38.0.tar.gz"

# Coroutines. The iOS SDK deprecates/withholds makecontext/swapcontext, so
# QEMU's ucontext coroutine backend needs this reimplementation. UTM's fork is
# pinned because it carries the Darwin/arm64 assembly fixes.
LIBUCONTEXT_REPO="https://github.com/utmapp/libucontext.git"
LIBUCONTEXT_COMMIT="9b1d8f01a6e99166f9808c79966abe10786de8b6"

# User-mode networking (virtio-net + slirp inside the guest's subnet).
SLIRP_SRC="https://github.com/utmapp/libslirp/releases/download/v4.9.1-release-mirror/libslirp-v4.9.1.tar.gz"