# Linux x86_64 Kernel ROM

Nyxian slot ROM that boots a real x86-64 Linux kernel and drops you into an
interactive terminal. The guest runs inside **rish** — a pure-Rust, JIT-less
x86-64 interpreter — so no guest instruction is ever executed natively and the
guest has no access to iOS.

## Contents

- `manifest.plist` — Nyxian boot manifest: boot logo, slot paths, permissions,
  code-signing requirements (ABI 1, minimum Nyxian 0.11.5).
- `rom/` — Objective-C slot host image (`main`, exports `NXSlotMain`), the
  terminal UI, and the vendored rish C ABI (`rom/include/rish.h`).
- `assets/bootlogo.png` — boot logo shown by Nyxian at flash/load time.
- `guest-images.lock.tsv` — pinned guest image sizes, SHA-256 hashes, sources.
- `scripts/prepare-guest-images.sh` — stages the kernel + initramfs; can build
  the initramfs from rish or download a prebuilt release asset.
- `scripts/patches/rish-gnutar-compat.patch` — applied by
  `prepare-guest-images.sh` to rish's initramfs builder so it extracts the
  busybox/apk closure from the pinned Alpine minirootfs (whose tar members are
  stored with a leading `./`) under GNU tar, used by the ubuntu CI runner.

## Guest images

- Kernel: `vmlinuz-virt` from the pinned Alpine 3.24.1 netboot release,
  hash-verified, staged as `kernel/vmlinuz-virt-6.18.35`.
- Initramfs: rish's interactive container initramfs (busybox + guest agent),
  built by rish's own hash-verified builder. Set `RISH_INITRD_URL` and
  `RISH_INITRD_SHA256` to download a prebuilt asset instead.

### Alpine minirootfs `./`-prefixed members

The pinned Alpine v3.24 minirootfs stores its tar members with a leading `./`
(e.g. `./bin/busybox`). rish's upstream `build-container-initramfs.sh` selects
members by bare paths (`bin/busybox`), which bsdtar (macOS) matches but GNU tar
(ubuntu CI) does not — the build fails with `tar: bin/busybox: Not found in
archive` even though every asset verifies. `prepare-guest-images.sh` therefore
applies `scripts/patches/rish-gnutar-compat.patch` to the pinned builder,
switching the extraction to layout-agnostic `--wildcards '*/...'` patterns that
match both prefixed and bare member names.

## Build

    make validate          # plutil -lint manifest.plist (macOS)
    make rom.zip           # builds main + librish_ffi.a + rom.zip

Requires macOS with Xcode and Rust (`rustup target add aarch64-apple-ios`).
The initramfs build (`prepare-guest-images.sh`, or CI's ubuntu job) additionally
needs `squashfs-tools` and the `x86_64-unknown-linux-musl` Rust target. rish's
builder links the guest agent with `x86_64-linux-musl-gcc` (brew
`Filosottile/musl-cross/musl-cross` on macOS); on Linux install `musl-tools`
and point cargo at the wrapper first:

    sudo apt-get install -y squashfs-tools musl-tools
    rustup target add x86_64-unknown-linux-musl
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER=musl-gcc
    ./scripts/prepare-guest-images.sh

Set `RISH_ROOT` if the rish checkout is not at `build/rish`.
`.github/workflows/build-rom.yml` does all of this in CI and uploads `rom.zip`.