---
title: Running Linux on iOS Without JIT
description: A long look at how I got a real Linux environment running on an iPhone without JIT compilation, using a native User-mode Linux kernel, a gadget-based userspace engine, and a graphics stack that ends on Apple's GPU.
date: 2026-11-12
author: Skylo, Kelly Inc.
tags: [ios, linux, arm64, systems, graphics]
font: mono
weight: 300
width: 110
---

# Running Linux on iOS Without JIT

When people hear "Linux on an iPhone", they usually picture one of two things.

The first is a full system emulator like UTM. It pretends to be an entire computer: CPU, memory controller, disk controller, network card, interrupt controller, the lot. That works, and it's genuinely impressive, but without JIT every single guest instruction (kernel *and* userspace) has to be interpreted. On a stock iPhone that ends up painfully slow.

The second is something like iSH. iSH skips the kernel entirely. It emulates userspace programs and then fakes the kernel underneath by translating Linux system calls into something iOS understands. That's much lighter, but you're not really running Linux. You're running Linux programs on top of a reimplementation of a slice of the Linux kernel, and anything that touches the parts that weren't reimplemented just doesn't work.

Linuxed sits in between those two, and honestly that middle position is the whole reason it performs the way it does. This post is a long walk through the architecture: how the kernel runs, how userspace runs without generating code at runtime, how memory is handled, and how graphics and video end up on the actual GPU and media engine instead of being drawn in software.

It's a long one. Grab a coffee.

## The three approaches side by side

Before getting into details, here's the rough picture of where each approach puts the work.

| | Full system emulator (UTM without JIT) | Userspace emulator (iSH) | Linuxed |
|---|---|---|---|
| Kernel | Real Linux, fully emulated | Not real Linux, reimplemented syscalls | Real Linux, **native arm64** |
| Userspace | Emulated | Emulated | Executed through precompiled gadgets |
| Hardware | Emulated devices | None, mostly faked | Paravirtual devices backed by the host |
| Kernel speed | Slow | n/a | Native |
| Linux compatibility | Excellent | Partial | Excellent |
| Graphics | Usually software | Basically none | Real GPU through Vulkan on Metal |
| Needs JIT to be fast | Yes | Helps a lot | No |

The trick is noticing that the kernel and the userspace programs don't have to be treated the same way. The kernel is something we build ourselves, from source, so we can compile it for the phone. The userspace programs come from Debian or wherever, and we have no say in how they were compiled. So we split them up and handle each in the cheapest way iOS allows.

## The kernel is not emulated

The core idea is User-mode Linux, or UML.

UML is a port of the Linux kernel that's been around for a very long time. Instead of targeting real hardware like x86 or arm64 boards, it targets "a normal process running on another OS". Where a normal kernel would program a page table, UML asks the host to map memory. Where a normal kernel would take a hardware timer interrupt, UML gets a signal or a host timer. Where a normal kernel would talk to a disk controller, UML reads and writes a file. The kernel's own logic is untouched; only the very bottom layer that talks to "hardware" is swapped out.

Historically UML has been a Linux-on-Linux thing on x86. For Linuxed, the host side had to be written from scratch for Apple platforms on arm64. We compile a real, mainline 6.18 kernel to native arm64 code and link it into an iOS runtime framework.

That means the kernel itself runs at full native speed. All of this is real Linux, compiled for the phone's CPU and executing directly:

- the scheduler
- the page cache and the VFS
- every filesystem (ext4, EROFS, overlayfs, tmpfs and friends)
- namespaces and cgroups
- the full TCP/IP networking stack
- SELinux and the rest of the security modules
- the DRM graphics subsystem and V4L2 video subsystem

Nothing about the kernel is interpreted. When a program calls `open()`, the actual Linux `open()` path runs, natively, at the same speed it would run on an arm64 server (well, a phone-sized arm64 server).

This matters more than it sounds. On a typical desktop workload a surprising amount of time is spent inside the kernel: page faults, file lookups, pipes, futexes, socket buffers, memory management. In a full system emulator every one of those costs emulation overhead. Here they cost nothing extra.

### Getting the kernel's code past iOS

There's a catch, though, and it's a big one. iOS doesn't let an app map arbitrary memory as executable. Code signing is enforced page by page. If a page isn't covered by a valid signature from the app bundle, the CPU isn't allowed to execute it. That's the whole reason JIT is restricted on iOS in the first place.

A kernel is a big blob of machine code. You can't just load it from a file and jump to it, because that freshly loaded memory isn't signed.

So the kernel's ELF image is carried inside the signed framework itself, in its `__TEXT` segment. Because it's part of the signed binary, iOS is happy to execute it. It went through the same signing and review as the rest of the app.

The problem is that the kernel was linked to expect its code at specific addresses, and those don't match wherever iOS decided to load the framework. The runtime solves that by aliasing those already-signed executable pages into the place the kernel expects to run from. Same physical pages, same signature, just visible at a second address.

No new code is ever created. We just point at code Apple has already approved.

| Step | What happens | Who signs it |
|---|---|---|
| Build | Kernel compiled to arm64 ELF | n/a |
| Package | ELF embedded in framework `__TEXT` | Developer, at build time |
| Install | App installed on device | Apple, at install time |
| Boot | Runtime aliases signed pages to kernel's link address | Already signed, nothing new |
| Run | Kernel executes natively | n/a |

### Kernel builds are artifacts, not something the app does

One practical detail: the iOS app never builds a kernel. Kernels are built separately from a pinned upstream revision plus a series of patches, and the result is an accepted, prebuilt bundle. The app build just consumes that bundle. That keeps the app build fast and reproducible, and it means a given app version always ships a known kernel.

## Userspace without JIT

The kernel is native, but the programs running on top of it (your shell, your desktop, your browser) are ordinary Linux binaries. They were compiled for arm64 Linux, which is the same CPU architecture as the phone, so you might think "just run them".

The problem is that those binaries are files on a disk image. Loading them into memory and jumping to them is exactly the "execute unsigned memory" thing iOS refuses to do. So even though the instructions are the right architecture, we can't execute them directly. Something has to stand in for the CPU.

On a stock iPhone we also can't generate machine code at runtime, which rules out a classic JIT that would translate guest code into fresh host code.

### Gadgets

Instead, userspace runs on what we call the gadget engine. The idea comes from iSH, and it's a really neat one.

Rather than translating guest instructions into new host instructions, we translate them into a stream of pointers to small, precompiled routines (gadgets) that already exist in the signed binary. Each gadget does one small piece of work, like a load, an add or a branch, and then jumps straight to the next one.

Here's a simplified example. Say the guest has this:

```asm
ldr  x0, [x1, #8]
add  x0, x0, #1
str  x0, [x1, #8]
```

A JIT would emit three or four brand new host instructions. The gadget engine instead emits something like:

| Slot | Contents | Kind |
|---|---|---|
| 0 | pointer to `gadget_load64` | code pointer |
| 1 | source register = x1, offset = 8, dest = x0 | data |
| 2 | pointer to `gadget_add_imm` | code pointer |
| 3 | register = x0, immediate = 1 | data |
| 4 | pointer to `gadget_store64` | code pointer |
| 5 | source register = x0, base = x1, offset = 8 | data |
| 6 | pointer to `gadget_next_block` | code pointer |

Every one of those `gadget_*` routines was compiled ahead of time and lives in the signed app. The engine runs the first one, which reads its operands from the stream, does its work, and then jumps to whatever pointer comes next.

The important property is that the gadget stream is **data, not code**. It lives in ordinary writable memory, so iOS has no objection to it. All the executable code involved was compiled ahead of time and signed with the app. We're not breaking any rule; we're just being clever about what counts as a "program".

### Why this is faster than a plain interpreter

A naive interpreter reads an instruction, decodes it, looks up what to do in a giant `switch`, does it, then goes back to the top and repeats. That's slow for a few reasons: decoding is expensive, the central `switch` is one indirect branch the CPU can barely predict, and every instruction pays the full overhead.

The gadget engine gets rid of most of that.

| Technique | What it does | Why it helps |
|---|---|---|
| **Block caching** | Guest code is decoded once into a gadget block and reused | Hot loops don't pay the decode cost again and again |
| **Block linking** | Blocks that branch to each other are linked directly | Control flows block to block without returning to a dispatcher |
| **Threaded dispatch** | Each gadget ends by jumping to the next one | Many separate indirect branches, each predictable on its own, instead of one shared unpredictable one |
| **Real SMP** | Multiple guest vCPUs mapped onto real host threads | Multithreaded workloads actually spread across the phone's cores |
| **Whole-program optimisation** | Gadgets built with interprocedural optimisation | The compiler sees across gadgets and the helpers they call |

The threaded dispatch point deserves a bit more explanation because it's not obvious. Modern CPUs predict where an indirect branch is going based on where that particular branch went before. With a central `switch`, there's one branch serving every instruction type, so its history is a mess and it guesses wrong all the time. With threaded dispatch, every gadget has its own tail jump. The jump at the end of "compare" learns that it's usually followed by "conditional branch", and so on. The predictor ends up doing a lot of the dispatch work for free.

The SMP point is also a big deal in practice. A lot of emulators run every guest CPU on one host thread and take turns. Here each vCPU is a real host thread, so if you run `make -j4` the phone's performance cores actually get used.

### How a gadget engine handles the hard parts

The simple example above makes it look easy. A few things are not:

- **Memory access.** Every guest load and store has to go through the guest's address space, which means translating a guest virtual address into somewhere in host memory and handling faults. The kernel owns the guest's page tables, so a fault turns into a real Linux page fault handled by the real kernel.
- **System calls.** When a guest program executes `svc #0`, the gadget for that hands control to the UML kernel, which runs the syscall natively and returns.
- **Self-modifying code.** If a program writes to memory that already has a cached gadget block, that block is stale and has to be thrown away. This is the expensive case, and it's why JIT-heavy programs hurt (more on that later).
- **SIMD and floating point.** arm64 has a big vector instruction set, and real software (compression, crypto, media, browsers) uses a lot of it. Each of those needs gadgets too. A missing instruction isn't something we skip or work around; a guest program hitting an illegal instruction is treated as a bug to fix, full stop.

### Measured, not guessed

None of this was guesswork. The project keeps a long optimisation history of every performance experiment, including the ones that didn't pan out. Each entry is basically: what I thought would help, what actually happened, and what I learned.

Some of the lessons were counterintuitive. Bigger caches, for example, sounded obvious but measured worse, because capacity was never the bottleneck. A larger cache just meant more memory touched and worse locality, without any extra hits to show for it. Changes only stay in when the numbers back them up.

### There's still a JIT, when you're allowed one

There is still an optional JIT engine for situations where the device actually permits runtime code generation. All executable memory in the project goes through one single small, audited piece of code, so the JIT doesn't get to sneak around the rules either. On a stock device, though, the gadget engine is what you're running, and it's fast enough for real desktops.

## Pages, memory and the host

### 4 KiB guests on a 16 KiB host

One detail that matters more than you'd think: Linux guests here use 4 KiB pages, while the iPhone uses 16 KiB pages.

| | Page size | Who decides |
|---|---|---|
| Guest Linux (arm64) | 4 KiB | Linux ABI expectations of most binaries |
| Apple host | 16 KiB | Apple, not configurable |

Why not just run the guest with 16 KiB pages? Linux on arm64 does support it. The problem is the ecosystem. A lot of binaries, and a lot of software with hand-tuned memory allocators, quietly assume 4 KiB. Run them on a 16K kernel and you get odd crashes, wasted memory, or things that refuse to start. Browsers and language runtimes are the usual culprits.

So the guest gets the boring, standard 4 KiB pages, and the runtime handles the mismatch by mapping guest pages inside host pages. Each host page holds four guest pages, and the runtime tracks them individually where it matters (permissions, faults, sharing). That keeps the guest ABI completely standard. Any normal arm64 Linux binary just works, with no special build.

This isn't a second "mode" or profile. There's exactly one kind of guest, and the host page handling is just an implementation detail of the host.

### Living inside the iOS memory budget

Memory is budgeted carefully as well. iOS doesn't swap app memory to disk the way a desktop OS would. If an app uses too much, the system just kills it. No warning dialog, no chance to save, it's gone.

So the runtime splits its budget up front instead of hoping for the best:

| Consumer | What it's for |
|---|---|
| Guest RAM | What Linux sees as its physical memory |
| GPU | Shared graphics buffers, textures, command streams |
| Translation caches | Decoded gadget blocks |
| Runtime heaps | The host side's own bookkeeping |

The settings screen only offers configurations that fit on the device you're actually holding. A phone with less RAM simply won't show you options that would get the app killed halfway through booting a desktop. I'd rather hide a setting than let someone pick one that silently crashes.

## Getting graphics onto the real GPU

This is the part people are usually most surprised by. A Linux desktop in Linuxed is drawn by the iPhone's GPU, not by the CPU.

That's a big deal. Software rendering a desktop at phone resolution is a lot of CPU work, and the CPU in our case is already busy running userspace through gadgets. Offloading drawing to the GPU frees up a huge amount of time for everything else.

### virtio-gpu

The guest sees a standard virtio-gpu device. This is the same virtual GPU Linux uses in normal virtual machines (QEMU, crosvm and friends), so the guest kernel's driver is just the regular upstream one. Nothing iPhone-specific leaks into the guest.

virtio-gpu by itself is just a transport. It's a way for the guest to hand the host buffers and command streams. What makes it useful is what the host does with them.

### The stack, layer by layer

Here's the full path from a Linux app to the Apple GPU:

| Layer | Runs in | Component | Job |
|---|---|---|---|
| App | Guest userspace | Your program | Calls OpenGL or Vulkan |
| GL on Vulkan | Guest userspace | Zink (Mesa) | Turns OpenGL / GLES into Vulkan |
| Vulkan driver | Guest userspace | Venus (Mesa) | Serialises Vulkan calls into a protocol |
| Transport | Guest kernel | virtio-gpu DRM driver | Ships commands and buffers to the host |
| Device | Host | virtio-gpu backend | Receives commands, manages resources |
| Vulkan on Metal | Host | KosmicKrisp (Mesa) | Implements Vulkan on top of Metal |
| GPU | Hardware | Apple GPU | Actually draws |

Going through it in words:

- **Vulkan through Venus.** The guest's Mesa driver speaks the Venus protocol, which forwards Vulkan calls to the host instead of trying to drive hardware itself. On the host they land in KosmicKrisp, Mesa's Vulkan driver implemented on top of Metal. So a Vulkan call in Linux ends up as Metal work on the Apple GPU.
- **OpenGL through Zink.** Most Linux desktop software still uses OpenGL, not Vulkan. OpenGL and OpenGL ES go through Zink, which implements OpenGL on top of Vulkan, which then goes through Venus as above. The guest gets OpenGL 4.6 and GLES 3.2, all ultimately running on Metal.
- **Shared memory instead of copies.** Graphics buffers are shared between guest and host through a shared memory aperture, rather than copied back and forth every frame. A single 4K frame buffer is tens of megabytes; copying several of those every frame would eat the CPU alive. With the aperture, the guest writes into memory the host GPU can already see. That's a big part of why this is usable at all.

### Honest feature reporting

The guiding rule for the graphics stack is honesty. The guest only sees features that actually work end to end, from Linux through Venus and KosmicKrisp to Metal.

Metal and Vulkan don't line up perfectly. There are features Vulkan has that Metal doesn't, or that Metal only does in some cases, or that behave slightly differently. The tempting thing is to paper over the gaps with a CPU fallback so the feature list looks complete.

I don't do that. Anything Metal can't do reliably is reported as unsupported instead of being faked in software, because a feature that silently falls back to the CPU is worse than one that isn't there. If an app knows a feature is missing, it can pick a different path. If the feature claims to exist but is secretly ten times slower, the app happily uses it and the whole thing crawls, and nobody can tell why.

| Situation | What the guest sees | Result |
|---|---|---|
| Feature works on Metal | Supported | Fast, on GPU |
| Feature partially works | Unsupported | App uses its own fallback |
| Feature would need a CPU emulation | Unsupported | App uses its own fallback |

### Video

Video works the same way. The guest has a virtio video device for H.264 and HEVC, exposed through the normal Linux V4L2 interfaces. On the host side, decoding and encoding go to Apple's VideoToolbox, which uses the phone's dedicated media hardware.

So a browser playing a video isn't decoding it on an emulated CPU, which would be hopeless. The phone's media engine does the work, the same one that plays videos in Safari, and the decoded frames go straight into GPU memory.

| Codec | Decode | Encode | Where it runs |
|---|---|---|---|
| H.264 | Yes | Yes | VideoToolbox hardware |
| HEVC | Yes | Yes | VideoToolbox hardware |

## Everything else

A few smaller pieces round it out. None of them are flashy, but each one needed real thought to fit inside iOS.

### Networking

Networking goes through libslirp. Slirp is a user-space TCP/IP implementation: the guest sends real Ethernet frames, and slirp turns its connections into normal host sockets. The guest has a full Linux network stack (real routing, real firewalls, real DNS resolution) and reaches the internet through the phone's Wi-Fi or mobile data.

That means no VPN profile, no special entitlement, and no root. To iOS it just looks like an app opening ordinary network connections.

### Storage

Storage uses read-only EROFS images with a writable ext4 overlay on top.

| Layer | Filesystem | Writable | Purpose |
|---|---|---|---|
| Base | EROFS | No | The OS image, compact and compressed |
| Overlay | ext4 | Yes | Everything you change or install |
| Combined | overlayfs | Yes | What the guest actually mounts |

EROFS is a read-only filesystem built for exactly this: small, compressed, and quick to read. Because the base system never changes, it stays compact. All your changes persist in a separate overlay file, which also means "factory reset" is just deleting one file. Start fresh whenever you want, and the base image is untouched.

### Lifecycle

Lifecycle is iOS-aware. Phone apps don't get to run forever in the background, and they really don't get to use the GPU in the background. Submitting GPU work while backgrounded is a quick way to get killed.

So when the app goes to the background, the guest's GPU work is held cleanly. Commands that were already in flight finish, new ones wait, and nothing is half-submitted. Depending on your settings, the guest is either paused entirely or kept running (without drawing) for as long as iOS allows. When you come back, the GPU picks up where it left off.

## Where it's slow

It's worth being upfront about the limits, because there are some, and pretending otherwise doesn't help anyone.

Workloads that generate their own code at runtime are the worst case for the gadget engine. That covers JavaScript engines, the Java JVM and similar runtimes.

Here's why. The gadget engine's whole speed trick is decoding code once and reusing it many times. A JIT inside the guest does the opposite. It constantly writes brand new machine code, runs it a few times, throws it away and writes more. Every bit of freshly generated code has to be decoded into a fresh gadget block before it can run, and every time the guest JIT overwrites old code, the cached block for it has to be thrown away. We pay the decode cost over and over and almost never get the reuse.

Heavy browser apps and Java games feel it most.

The funny consequence is that turning off the guest's JIT can make things faster. Running browsers with their JIT disabled actually helps here, since an interpreter is cheaper for us than a stream of brand new machine code. An interpreter is one fixed chunk of code that gets decoded once and then runs from the cache forever. So the Debian images ship browsers configured that way by default.

| Workload | How it feels | Why |
|---|---|---|
| Shell, coreutils, scripts | Good | Mostly kernel time and small hot loops |
| Compilers (gcc, clang, rustc) | Good | Large but stable code, caches well |
| Desktop environment | Good | Drawing goes to the GPU |
| Video playback | Good | Hardware decode |
| Lighter GUI apps | Good | Normal compiled code |
| Browsers, JIT disabled | Okay | Interpreter is cache friendly |
| Browsers, JIT enabled | Poor | Constant fresh code |
| Java / JVM apps and games | Poor | Constant fresh code |

Everything in the top half of that table runs well enough to feel like a real Linux machine in your pocket.

## Wrapping up

The whole design comes down to one idea: each part runs in the cheapest form iOS allows.

| Part | How it runs | Cost |
|---|---|---|
| Kernel | Native arm64, from signed code | Basically free |
| Userspace | Precompiled gadgets driven by data | Moderate, cached |
| Graphics | Vulkan and OpenGL forwarded to Metal | Runs on the GPU |
| Video | Forwarded to VideoToolbox | Runs on the media engine |
| Network | Slirp over normal sockets | Cheap |
| Storage | EROFS plus ext4 overlay | Cheap |

And the whole thing stays inside the rules. No jailbreak, no remote server streaming a desktop from somewhere else, and no runtime code generation unless the device allows it. Everything that executes was signed with the app, and everything else is just data.

If you've got questions, or you've tried it and something is broken, I'd love to hear about it.
