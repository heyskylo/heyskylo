#!/bin/bash
# Download + unpack every pmos engine dependency into
# build/engine/sources and build/engine/src.  Mirrors Husk's fetch_sources.sh.
set -u
PMOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$PMOS_ROOT/scripts/sources.sh"
DL="$PMOS_ROOT/build/engine/sources"
SRC="$PMOS_ROOT/build/engine/src"
mkdir -p "$DL" "$SRC"

fetch() {
    local url="$1" file="$DL/$(basename "$1")"
    if [ -s "$file" ]; then echo "[skip] $(basename "$file")"; return 0; fi
    echo "[get ] $(basename "$file")"
    curl -fL --retry 3 --retry-delay 5 -o "$file.part" "$url" || { echo "[FAIL] $url"; return 1; }
    mv "$file.part" "$file"
}

unpack() {
    local file="$DL/$(basename "$1")" stamp
    stamp="$SRC/.unpacked-$(basename "$file")"
    [ -f "$stamp" ] && { echo "[skip] unpack $(basename "$file")"; return 0; }
    echo "[tar ] $(basename "$file")"
    tar -xf "$file" -C "$SRC" || return 1
    touch "$stamp"
}

clone_ucontext() {
    local dir="$SRC/libucontext"
    if [ -d "$dir/.git" ]; then
        echo "[skip] libucontext (already cloned)"
    else
        echo "[git ] libucontext @ $LIBUCONTEXT_COMMIT"
        git clone --quiet "$LIBUCONTEXT_REPO" "$dir" || return 1
        ( cd "$dir" && git checkout --quiet "$LIBUCONTEXT_COMMIT" ) || return 1
    fi
}

rc=0
for u in "$FFI_SRC" "$ICONV_SRC" "$GETTEXT_SRC" "$GLIB_SRC" "$PIXMAN_SRC" "$SLIRP_SRC" "$QEMU_SRC"; do
    fetch "$u" || rc=1
done
for u in "$FFI_SRC" "$ICONV_SRC" "$GETTEXT_SRC" "$GLIB_SRC" "$PIXMAN_SRC" "$SLIRP_SRC" "$QEMU_SRC"; do
    unpack "$u" || rc=1
done
clone_ucontext || rc=1

[ "$rc" -eq 0 ] || { echo "[FAIL] fetch-engine.sh had errors" >&2; exit 1; }
echo "[ok  ] engine sources ready under build/engine/src"
ls -1 "$SRC"