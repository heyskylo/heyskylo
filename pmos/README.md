# postmarketOS Phone — Nyxian slot ROM

Boots a real **postmarketOS generic-x86_64** image with the **Phosh** phone DE
inside a JIT-accelerated QEMU VM on iPhone. The guest is a full kernel boot
from a disk image — not a container.

```
Nyxian bootloader
  └─ Slot A (this ROM)
       ├─ main                     host image (Objective-C, ABI 1)
       ├─ manifest.plist
       └─ assets/bootlogo.png
       └─ guest/postmarketos.img   downloaded + verified on first boot
       └─ Frameworks/…             engine dylib (engine milestone)
```

## Status

| Piece | State |
| --- | --- |
| Manifest (ABI 1, `NXSlotMain`, Nyxian ≥ 0.11.5) | ✅ |
| Boot flow UI: image check → Download button → progress bar on top → boot | ✅ |
| Download + SHA-256 verify against `guest-images.lock.tsv` | ✅ (tested) |
| On-device XZ decompression (vendored XZ-Embedded) | ✅ (tested against the real 1.45 GiB artifact) |
| Guest image pinned (URL + SHA-256, official Nura server) | ✅ pinned to a hash-verified `20260803-0207` build |
| CI (guest drift check + macOS build of `rom.zip`) | ✅ wired |
| **Engine: `libqemu-x86_64-softmmu.dylib`** (UTM fork `v10.0.12-utm`, TCG JIT + MTTCG, Metal display bridge, virtio-tablet) | ⏳ engine milestone |

The engine is the one outstanding milestone. The host already dlopens it at
runtime (nothing is linked), so every piece above builds and is CI-verified
without it.

## Boot flow

1. Slot loads → host checks `guest/postmarketos.img` (+ staging marker).
2. Missing → **Download button**; tapping downloads the `.img.xz` pinned in
   `guest-images.lock.tsv`, verifies SHA-256, and decompresses in-slot with
   the vendored decoder. The only chrome is a 4 px progress bar at the top.
3. Staged → boot the VM: UEFI (OVMF) + the staged disk, TCG JIT via the
   debugger-substrate split-W^X (StikJIT / StikDebug / TrollStore), MTTCG.
4. Full-screen Phosh surface, direct touch (virtio-tablet absolute). No
   gamepad, no keyboard buttons, no window bars.

## Speed strategy (how "make it faster?" is answered)

- **JIT, not TCG-less interpretation** — TCG translates x86→intermediate code
  and JIT-compiles it on-device; iOS has no hypervisor for third-party apps, so
  a debugger-granted split-W^X region (`brk #0xf00d` handshake, Husk's
  approach, iOS 16.4+) is the JIT enabler.
- **MTTCG** — multiple vCPUs translating/executing in parallel; `-smp 4`.
- **virglrenderer → Metal** — guest OpenGL rendered on the host GPU instead of
  a software framebuffer blit.
- **`tb-size` set once at init** (TCG flushes/grows rather than reallocating,
  per Husk's findings).

## Guest image pin

`guest-images.lock.tsv` pins the official artifact:

```
postmarketos.img.xz  1555991728  1d7a5104e4ada62e229293ebeb4c1154b50eccf8810e7f941fbb50af33fcf522  https://images.nura.eco/bpo/v25.12/generic-x86_64/phosh/20260803-0207/20260803-0207-postmarketOS-v25.12-phosh-25-generic-x86_64-lts.img.xz
```

Decompresses to a ~4,080,009,216-byte raw disk. Both the prepare script (CI /
local) and the on-device manager consume the same pin, so they cannot drift.

## Build

Requires macOS with Xcode (Nyxian SDK needed to run it at all).

```bash
make -C pmos validate                    # plutil manifest lint
make -C pmos                             # host image + rom.zip (no image inside)
make -C pmos guest                       # stage the guest image locally
bash pmos/scripts/prepare-guest-images.sh --verify-only    # cheap drift check
```

CI (`../../.github/workflows/build-pmos.yml`) runs the drift check on Ubuntu
and builds `rom.zip` on macOS.

## Layout

```
pmos/
├── manifest.plist                    ABI 1, bootloader-compatible
├── Makefile                          host image + rom.zip
├── guest-images.lock.tsv             pinned guest artifact (URL + SHA-256)
├── engine.lock.tsv                   Husk / utmapp-qemu / xz-embedded pins
├── rom/src/
│   ├── NXMainSlot.m                  ABI glue (NXSlotMain / CreateWindow / DidAppear)
│   ├── LindChain/Phone/
│   │   ├── NXPostmarketOSViewController.[hm]   boot flow UI
│   │   ├── NXGuestImageManager.[hm]            download → verify → decompress
│   │   ├── NXPMOSEngine.[hm]                   dlopen facade for the engine dylib
│   │   └── NXSurfaceView.[hm]                  full-screen surface (Metal-backed later)
│   └── xz/                            XZ-Embedded decoder (0BSD) + streaming driver
├── scripts/prepare-guest-images.sh
└── assets/bootlogo.png
```

## Engine milestone (the remaining work)

1. Build `libqemu-x86_64-softmmu.dylib` from `utmapp/qemu` **`v10.0.12-utm`**
   with `-Dshared_lib=true` (Husk builds the same fork for aarch64; the x86_64
   softmmu target is what pmOS generic needs), pinned in `engine.lock.tsv`.
2. Grant JIT via the debugger handshake (`brk #0xf00d`, x16=1) then `vm_remap`
   the RW alias — Husk's exact substrate.
3. Implement the boot driver behind `NXPMOSEngine`: `qemu_init_config` with
   `{ "machine":"q35", "smp":4, "mem":4096, "disk":{…}, "tcg":{ tb_size:…,
   mttcg:true }, "uefi":"OVMF.fd", display/touch bridge }`, then
   `qemu_main_loop` on a background thread.
4. Feed `DisplayChangeListener` frames into `NXSurfaceView` via CAMetalLayer
   and forward touches as virtio-tablet absolute input.
5. Ship the dylib (+ OVMF.fd) in the slot `Frameworks/` directory; CI builds
   them alongside the host image.

## License

GPL-2.0-or-later, matching the vendored QEMU engine underneath.