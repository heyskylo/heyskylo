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

## Guest images

- Kernel: `vmlinuz-virt` from the pinned Alpine 3.24.1 netboot release,
  hash-verified, staged as `kernel/vmlinuz-virt-6.18.35`.
- Initramfs: rish's interactive container initramfs (busybox + guest agent),
  built by rish's own hash-verified builder. Set `RISH_INITRD_URL` and
  `RISH_INITRD_SHA256` to download a prebuilt asset instead.

## Build

    make validate          # plutil -lint manifest.plist (macOS)
    make rom.zip           # builds main + librish_ffi.a + rom.zip

Requires macOS with Xcode and Rust (`rustup target add aarch64-apple-ios`);
the initramfs build additionally needs `squashfs-tools` and the
`x86_64-unknown-linux-musl` Rust target. Set `RISH_ROOT` if the rish checkout
is not at `build/rish`. `.github/workflows/build-rom.yml` does all of this in
CI and uploads `rom.zip`.