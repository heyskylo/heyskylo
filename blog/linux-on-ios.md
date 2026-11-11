---
title: Running Linux on iOS Without JIT
description: A technical deep dive into running a Linux environment on iOS using native ARM64 execution, an interpreted userspace, and a few creative workarounds.
date: 2026-11-12
author: Skylo
tags: [ios, linux, arm64, systems, development]
font: mono
weight: 300
width: 110
---

# Running Linux on iOS Without JIT

**A real Linux environment, running on an iPhone, without relying on Just-In-Time compilation.**

Running Linux on iOS has always been an interesting engineering challenge. Apple's restrictions around executable memory, code signing, and JIT compilation make traditional virtualization approaches difficult to implement, especially without special entitlements.

I wanted to explore a different approach: instead of trying to make iOS behave like a conventional desktop virtualization host, build an execution environment around the limitations of the platform.

The result is a Linux environment capable of running on iOS without requiring JIT compilation.

---

## 01 / The architecture

The most important design decision was separating kernel execution from userspace execution.

Rather than attempting to emulate an entire computer, the implementation uses a hybrid execution model:

| Component | Execution model |
|---|---|
| Linux kernel | Native ARM64 |
| Userspace | Software interpretation |
| CPU architecture | ARM64 |
| Memory | Host-managed memory |
| JIT compilation | Not required |

This avoids the overhead and complexity of full hardware emulation while keeping the execution model compatible with iOS restrictions.

### Kernel execution

The Linux kernel is built for the device's ARM64 architecture, allowing its instructions to execute natively rather than being translated through a CPU emulator.

This is particularly important on mobile hardware, where unnecessary emulation overhead can quickly become a performance bottleneck.

The kernel handles the familiar responsibilities:

- Process and task management.
- Virtual memory management.
- Scheduling.
- Filesystem operations.
- Kernel-level system interfaces.

### Userspace execution

Userspace requires a different approach.

Since arbitrary executable code cannot simply be generated and executed through a conventional JIT on iOS, guest userspace instructions are handled through an interpreter.

The interpreter fetches and decodes guest instructions, then implements their behavior using operations available to the host process.

Conceptually:

```text
Guest application
       |
       v
Instruction fetch
       |
       v
Instruction decoder
       |
       v
Software interpreter
       |
       v
Native ARM64 operations
       |
       v
iOS host environment
```

This allows userspace execution without dynamically generating executable machine code.

---

## 02 / Working around the JIT limitation

One of the biggest challenges was designing around Apple's executable memory restrictions.

Traditional JIT engines generally rely on allocating memory, generating machine instructions, and transitioning that memory into an executable state.

That approach isn't something I wanted this project to depend on.

Instead, interpretation provides a different execution path.

The interpreter processes instructions without producing dynamically generated executable code.

This has trade-offs:

- More instruction-dispatch overhead.
- Potentially lower userspace performance.
- Greater implementation complexity.
- No dependency on JIT entitlements.

The important distinction is that **not requiring JIT doesn't mean not executing native code**.

The kernel can still execute native ARM64 instructions while userspace follows a separate interpreted execution path.

---

## 03 / Memory and execution

Memory management is another important part of making the environment work reliably.

The implementation has to maintain a distinction between guest execution state and the host process's address space.

Some of the important considerations include:

- Guest memory representation.
- Register and instruction state.
- Memory access validation.
- Stack management.
- Synchronization between execution threads.
- Handling exceptions and invalid instructions.

This becomes especially important when running more than simple test programs.

A working execution environment needs to handle much more than just decoding instructions. It needs to maintain consistent state across the entire execution lifecycle.

---

## 04 / Why iOS makes this interesting

iOS isn't designed to be a general-purpose virtualization host.

There are platform restrictions around executable memory, process isolation, entitlements, and access to lower-level system interfaces.

That means solutions designed for Linux desktops don't necessarily translate directly to iOS.

The interesting part of this project was figuring out how to work within those restrictions instead of treating them as something that could simply be bypassed.

By using native ARM64 execution where possible and interpretation where necessary, the implementation avoids depending on conventional JIT-based execution.

---

## 05 / Development with Claude

A surprising amount of the development process involved working alongside Claude.

I used it to help investigate implementation details, reason about execution models, debug difficult issues, and iterate on different approaches.

It was particularly useful when dealing with unfamiliar low-level code and tracking down problems that weren't immediately obvious.

Of course, AI doesn't magically produce a working Linux environment. There was still a lot of experimentation, debugging, testing, and understanding what was actually happening under the hood.

But having that additional development assistance made exploring such a complicated problem considerably more approachable.

---

## 06 / What's next?

Getting Linux running on iOS without JIT is a pretty interesting milestone, but there's still plenty of room to improve.

Some areas worth exploring further:

- [ ] Improving userspace interpretation performance.
- [ ] Expanding compatibility with Linux applications.
- [ ] Improving filesystem integration.
- [ ] Better networking support.
- [ ] More robust process and thread handling.
- [ ] Improving overall stability and resource management.

The long-term goal is to make the experience as practical as possible, rather than simply proving that it can boot.

---

## Final thoughts

I think people sometimes underestimate how much can be done on iOS when you approach the platform differently.

Instead of trying to recreate a conventional desktop virtualization stack, this project explores a hybrid approach that takes advantage of native ARM64 execution while avoiding JIT entirely.

And yes, apparently you can run Linux on an iPhone without JIT.

A little help from Claude, a lot of debugging, and quite a bit of curiosity.

**More experiments coming soon.**

— Skylo

*Founder of Kelly Inc.*
