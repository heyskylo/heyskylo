#!/usr/bin/env bash
#
# prepare-guest-images.sh — download, verify, and decompress the pinned
# postmarketOS guest image into build/guest/.
#
# Modes:
#   ./scripts/prepare-guest-images.sh          full stage (download + sha256
#                                              + xz decompress)
#   ./scripts/prepare-guest-images.sh --verify-only
#                                              cheap drift check: fetch the
#                                              official .sha256 sidecar and
#                                              compare it with the lock pin.
#
# Reads the lock from guest-images.lock.tsv so the script and the ROM host
# never drift apart. The ROM itself performs the same download/verify/decode
# on device (LindChain/Phone/NXGuestImageManager), using the identical pin.

set -euo pipefail

cd "$(dirname "$0")/.."

LOCK=guest-images.lock.tsv
STAGE=build/guest

entry() {
    awk -F '\t' -v name="$1" '$1 == name && $1 !~ /^#/ && $0 !~ /^#/ { print; exit }' "$LOCK"
}

read entry_line <<< "$(entry postmarketos.img.xz)" || entry_line=""
if [ -z "$entry_line" ]; then
    echo "error: postmarketos.img.xz not found in $LOCK" >&2
    exit 1
fi
read -r name size sha256 source <<< "$entry_line"

mkdir -p "$STAGE"

if [ "$1" = "--verify-only" ]; then
    echo "--- verify-only drift check ---"
    sidecar="${source}.sha256"
    echo "fetching: $sidecar"
    remote=$(curl -fsSL --retry 3 "$sidecar" | awk '{ print $1; exit }')
    echo "remote  sha256: $remote"
    echo "pinned  sha256: $sha256"
    if [ "$remote" != "$sha256" ]; then
        echo "MISMATCH: the pinned image changed upstream — update guest-images.lock.tsv" >&2
        exit 1
    fi
    echo "pin still matches the official image."
    exit 0
fi

if [ $# -ne 0 ]; then
    echo "usage: $0 [--verify-only]" >&2
    exit 2
fi

echo "--- downloading ---"
echo "artifact: $name ($size bytes)"
echo "source:   $source"
curl -fL --retry 5 -o "$STAGE/$name" "$source"

echo "--- verifying sha256 ---"
actual=$(shasum -a 256 "$STAGE/$name" | awk '{ print $1 }')
echo "pinned  sha256: $sha256"
echo "actual  sha256: $actual"
[ "$actual" = "$sha256" ] || { echo "SHA256 MISMATCH" >&2; exit 1; }

echo "--- decompressing ---"
command -v xz >/dev/null 2>&1 || { echo "error: xz-utils required" >&2; exit 1; }
xz -d -k -T0 "$STAGE/$name"
raw="${name%.xz}"
echo "staged: $STAGE/$raw ($(stat -c %s "$STAGE/$raw") bytes)"
echo "--- done ---"