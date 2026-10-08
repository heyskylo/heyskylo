#!/bin/bash
# Copy pmos's own engine sources into the QEMU tree and wire them into its
# meson build, so the resulting libqemu-x86_64-softmmu.dylib carries:
#   - the split-W^X JIT allocator (nxp-ios-jit.c + nxp-brk.S, used by
#     tcg/region.c), and
#   - the DisplayChangeListener frame/input bridge (nxp-display.c).
# Idempotent: safe to re-run after editing rom/src/engine/.
#
# Mirrors Husk's scripts/integrate_husk.sh (Leviidev/Husk, GPL-2.0-or-later).
set -euo pipefail
PMOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$PMOS_ROOT/build/engine/src"
Q="$SRC/qemu-10.0.12-utm"
ENGINE_SRC="$PMOS_ROOT/rom/src/engine"

[ -d "$Q" ] || { echo "QEMU source tree missing; run fetch-engine.sh first" >&2; exit 1; }

echo "[cp  ] JIT substrate -> tcg/"
cp "$ENGINE_SRC/nxp-ios-jit.c" \
   "$ENGINE_SRC/nxp-ios-jit.h" \
   "$ENGINE_SRC/nxp-brk.S" "$Q/tcg/"

# region.c is patched in place rather than copied, so a re-extracted QEMU tree
# would silently lose it -- and the symptom (QEMU falling back to an RWX mmap
# and failing with EPERM) does not obviously point back here. Apply idempotently.
if grep -q "alloc_code_gen_buffer_splitwx_nxp_ios" "$Q/tcg/region.c"; then
    echo "[skip] tcg/region.c already patched"
else
    echo "[patch] tcg/region.c <- nxp-qemu-ios-jit.patch"
    patch --batch --forward --silent "$Q/tcg/region.c" \
        < "$PMOS_ROOT/patches/nxp-qemu-ios-jit.patch" \
        || { echo "  FAILED to apply region.c patch" >&2; exit 1; }
fi

echo "[cp  ] display bridge -> ui/"
cp "$ENGINE_SRC/nxp-display.c" \
   "$ENGINE_SRC/nxp-display.h" "$Q/ui/"

python3 - "$Q" <<'PY'
import pathlib, sys
q = pathlib.Path(sys.argv[1])

# tcg/meson.build: nxp-ios-jit.c + nxp-brk.S alongside region.c
p = q / "tcg/meson.build"
s = p.read_text()
if "nxp-brk.S" not in s:
    old = "tcg_ss.add(files(\n"
    assert old in s, "tcg/meson.build shape changed"
    s = s.replace(old, old + "  'nxp-brk.S',\n", 1)
    if "nxp-ios-jit.c" not in s:
        s = s.replace(old, old + "  'nxp-ios-jit.c',\n", 1)
    p.write_text(s)
    print("  tcg/meson.build: added nxp sources")
else:
    print("  tcg/meson.build: already wired")

# ui/meson.build: the display bridge
p = q / "ui/meson.build"
s = p.read_text()
if "nxp-display.c" not in s:
    old = "system_ss.add(files(\n"
    assert old in s, "ui/meson.build shape changed"
    s = s.replace(old, old + "  'nxp-display.c',\n", 1)
    p.write_text(s)
    print("  ui/meson.build: added nxp-display.c")
else:
    print("  ui/meson.build: already wired")
PY

# tcg/region.c: a second way to get executable memory.
#
# The dual RW/RX mapping needs a debugger attached (StikDebug + Universal JIT
# script). That is required on a device with TXM, and it is merely one of two
# options everywhere else: with CS_DEBUGGED set, iOS still honours a plain
# MAP_JIT mapping toggled via the APRR comm page (tcg-apple-jit.h), which is
# the route the built-in StikJIT on iOS 26+ provides.
#
# Patched here rather than in nxp-qemu-ios-jit.patch because that patch is
# applied with `patch` and skipped once it has been, so an addition to it would
# never reach a tree that was already patched.
python3 - "$Q" <<'PY_JITFALLBACK'
import pathlib, sys
q = pathlib.Path(sys.argv[1])
p = q / "tcg/region.c"
s = p.read_text()

old = """        /*
         * If splitwx force-on (1), fail;
         * if splitwx default-on (-1), fall through to splitwx off.
         */
        if (splitwx > 0) {
            return -1;
        }
        error_free_or_abort(errp);"""
new = """        /*
         * If splitwx force-on (1), fail;
         * if splitwx default-on (-1), fall through to splitwx off.
         *
         * pmos: on iOS, fall through either way.
         *
         * The dual RW/RX mapping above needs a trap servicer attached and
         * actively servicing brk requests. That is required on a device with
         * TXM, and it is merely one of two options everywhere else: with
         * CS_DEBUGGED set, iOS still honours a plain MAP_JIT mapping toggled
         * with the APRR comm page, which is the path below and the one UTM
         * uses. pmos forces splitwx on because without it TCG goes straight to
         * an RWX mmap that iOS refuses -- but forcing it must not throw away
         * the MAP_JIT route: a launch with the built-in StikJIT enabled gets
         * CS_DEBUGGED without a trap servicer, so the first route fails and
         * the second, which would have worked, was never tried.
         */
#if defined(__APPLE__) && TARGET_OS_IPHONE
        fprintf(stderr, "[nxp-jit] dual mapping unavailable; trying MAP_JIT "
                        "instead (works without a trap servicer, but not "
                        "on a device with TXM)\\n");
        fflush(stderr);
        error_free_or_abort(errp);
        splitwx = 0;
#else
        if (splitwx > 0) {
            return -1;
        }
        error_free_or_abort(errp);
#endif"""
if old in s:
    s = s.replace(old, new, 1)
    p.write_text(s)
    print("  tcg/region.c: iOS falls back to MAP_JIT when the dual mapping fails")
elif "trying MAP_JIT" in s:
    print("  tcg/region.c: MAP_JIT fallback already present")
else:
    raise SystemExit("tcg/region.c: splitwx fallback shape changed")
PY_JITFALLBACK

python3 - "$Q" <<'PY2'
import pathlib, sys
q = pathlib.Path(sys.argv[1])

# system/qemu.symbols is the authoritative export list for the shared-lib build.
# On darwin meson seds it into an ld64 -exported_symbols_list, so a symbol
# absent from here stays local no matter what visibility attribute it carries.
p = q / "system/qemu.symbols"
s = p.read_text()

import re as _re
wanted = [
    "nxp_display_init",
    "nxp_display_lock_frame",
    "nxp_display_unlock_frame",
    "nxp_display_sequence",
    "nxp_display_set_ui_size",
    "nxp_display_guest_size",
    "nxp_display_send_pointer",
    "nxp_display_send_key",
    "nxp_display_request_update",
    "nxp_ios_jit_prewarm",
    "nxp_ios_jit_install_trap_handler",
    "nxp_ios_jit_is_available",
    "nxp_ios_jit_mapjit_works",
    "nxp_ios_jit_detach",
    "nxp_ios_jit_log_footprint",
    "nxp_ios_available_memory",
]
# Prune stale nxp names (from earlier runs of this script), keeping QEMU's
# own exports untouched.
_present = _re.findall(r"^\s*(nxp_\w+);", s, _re.M)
for _stale in [n for n in _present if n not in wanted]:
    s = _re.sub(r"^\s*" + _stale + r";\n", "", s, flags=_re.M)
    print("  system/qemu.symbols: pruned stale " + _stale)

missing = [w for w in wanted if f"  {w};" not in s]
if missing:
    assert s.lstrip().startswith("{"), "qemu.symbols shape changed"
    idx = s.index("{") + 1
    s = s[:idx] + "\n" + "".join(f"  {w};\n" for w in missing) + s[idx:].lstrip("\n")
    p.write_text(s)
    print(f"  system/qemu.symbols: exported {len(missing)} nxp symbols")
else:
    print("  system/qemu.symbols: already exported")
PY2

echo "[ok  ] integrated"