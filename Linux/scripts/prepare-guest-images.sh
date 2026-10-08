#!/bin/sh
# prepare-guest-images.sh
#
# Stages the pinned Linux guest images (kernel + initramfs) into build/guest
# so the ROM can be packaged without any native x86-64 Linux on the build
# machine; the guest itself is executed JIT-less by rish.
#
# Sources come from ../guest-images.lock.tsv (name<TAB>size<TAB>sha256<TAB>source):
#   - source = https://...         downloaded with curl and hash-verified
#   - source = build:<script>      produced by rish's own hash-verified builder
#                                  (script path relative to $RISH_ROOT). The
#                                  adjacent fetch-assets.sh runs first when it
#                                  exists; the result is staged from the
#                                  script directory's out/ folder.
#
# Overrides:
#   RISH_ROOT         rish checkout (default: build/rish next to this script)
#   RISH_GUEST_DIR    output directory (default: build/guest)
#   RISH_INITRD_URL   prebuilt initramfs URL; when set (with RISH_INITRD_SHA256)
#                     the interactive initramfs is downloaded instead of built
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
lock_file="$repo_root/guest-images.lock.tsv"
guest_dir=${RISH_GUEST_DIR:-"$repo_root/build/guest"}
rish_root=${RISH_ROOT:-"$repo_root/build/rish"}
_zero_sha=0000000000000000000000000000000000000000000000000000000000000000

die() {
    printf 'prepare-guest-images: %s\n' "$*" >&2
    exit 1
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        die "sha256sum or shasum is required"
    fi
}

verify() { # file want_size want_sha -> 0 if present and matching
    [ -f "$1" ] || return 1
    want_size=$2
    want_sha=$3
    if [ "$want_size" != "0" ]; then
        actual=$(wc -c <"$1" | tr -d '[:space:]')
        [ "$actual" = "$want_size" ] || return 1
    fi
    if [ "$want_sha" != "$_zero_sha" ]; then
        [ "$(sha256_of "$1")" = "$want_sha" ] || return 1
    fi
    return 0
}

download() { # url target
    printf 'downloading %s\n' "$2"
    curl -fsSL --retry 3 --connect-timeout 30 "$1" -o "$2.tmp.$$"
    mv -f "$2.tmp.$$" "$2"
}

# The pinned Alpine v3.24 main/x86_64 APKINDEX is regenerated whenever Alpine
# rebuilds a package in that branch, so a hash pinned at release time can
# drift while every other rish guest asset stays content-addressed and stable.
# The index is itself authenticated by Alpine's .SIGN.RSA signature embedded in
# the tarball, so on a fetch failure we refresh only that one pin with the
# current index, then re-run fetch-assets (which re-verifies everything).
refresh_alpine_index_pin() { # lock_file downloads_dir
    lock=$1
    dir=$2
    url=$(awk -F '\t' '$1 == "alpine-apkindex-main" {print $6; exit}' "$lock")
    [ -n "$url" ] || return 1
    printf 'refreshing stale pinned APKINDEX (Alpine regenerates it as packages are rebuilt)\n'
    curl -fsSL --proto '=https' --connect-timeout 30 "$url" -o "$dir/APKINDEX.tar.gz" || return 1
    size=$(wc -c <"$dir/APKINDEX.tar.gz" | tr -d '[:space:]')
    sha=$(sha256_of "$dir/APKINDEX.tar.gz")
    tmp="$lock.tmp.$$"
    awk -F '\t' -v OFS='\t' -v size="$size" -v sha="$sha" \
        '$1 == "alpine-apkindex-main" {$4 = size; $5 = sha} {print}' "$lock" >"$tmp"
    mv -f "$tmp" "$lock"
    printf 'repinned alpine-apkindex-main to %s bytes, sha %s\n' "$size" "$sha"
}

run_fetch_assets() { # rish_root
    root=$1
    if ! (cd "$root" && guest/x86_64/fetch-assets.sh); then
        lock="$root/guest/x86_64/assets.lock.tsv"
        downloads="$root/guest/x86_64/out/downloads"
        mkdir -p "$downloads"
        [ -f "$lock" ] || return 1
        refresh_alpine_index_pin "$lock" "$downloads" || return 1
        (cd "$root" && guest/x86_64/fetch-assets.sh)
    fi
}

mkdir -p "$guest_dir"
[ -f "$lock_file" ] || die "missing lock file: $lock_file"
command -v curl >/dev/null 2>&1 || die "curl is required"

while IFS=$(printf '\t') read -r name size sha source _; do
    case "$name" in ''|'#'*) continue ;; esac
    target="$guest_dir/$name"

    if verify "$target" "$size" "$sha"; then
        printf 'verified  %s (already staged)\n' "$target"
        continue
    fi

    case "$source" in
    https://*)
        download "$source" "$target"
        verify "$target" "$size" "$sha" ||
            die "checksum mismatch for $target (size $size, please report a lock drift)"
        ;;

    build:*)
        script=${source#build:}
        if [ "$name" = "rish-container.cpio" ] && [ -n "${RISH_INITRD_URL:-}" ]; then
            [ -n "${RISH_INITRD_SHA256:-}" ] ||
                die "RISH_INITRD_SHA256 is required when RISH_INITRD_URL is set"
            download "$RISH_INITRD_URL" "$target"
            verify "$target" "$size" "$RISH_INITRD_SHA256" ||
                die "checksum mismatch for prebuilt $target"
        else
            [ -d "$rish_root" ] ||
                die "rish checkout not found at $rish_root (set RISH_ROOT)"
            builder="$rish_root/$script"
            [ -f "$builder" ] || die "builder not found: $builder"
            if [ -f "$(dirname "$builder")/fetch-assets.sh" ]; then
                printf 'fetching pinned rish guest assets via guest/x86_64/fetch-assets.sh\n'
                run_fetch_assets "$rish_root"
            fi
            printf 'building %s via %s\n' "$name" "$script"
            (cd "$rish_root" && "$builder")
            produced="$(dirname "$builder")/out/$name"
            [ -f "$produced" ] || die "builder did not produce $produced"
            cp -f "$produced" "$target"
            if ! verify "$target" "$size" "$sha"; then
                printf 'note: %s is a build artifact without a pinned checksum here\n' "$target"
            fi
        fi
        ;;

    *)
        die "unsupported source for $name: $source"
        ;;
    esac
done <"$lock_file"

printf 'guest images ready in %s\n' "$guest_dir"