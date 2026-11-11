---
title: Running Linux on iOS Without JIT
description: A look into how I got a Linux environment running on an iPhone without JIT compilation, using ARM64 execution and a custom userspace execution layer.
date: 2026-11-12
author: Skylo
tags: [ios, linux, arm64, rust, systems]
font: mono
weight: 300
width: 110
---

# Running Linux on iOS Without JIT

**Getting Linux running locally on an iPhone, without relying on JIT compilation.**

I've been experimenting with low-level development on iOS for a while, and eventually I started wondering how far I could push things without relying on the usual JIT-based approaches.

I wanted to get a Linux environment running directly on an iPhone. Not through SSH, not through a remote server, and not through some cloud-based workaround.

Actually running it locally.

After quite a bit of experimenting, debugging, and help from Claude, I managed to get it working.

<aside>
**Project overview**

| Property | Details |
|---|---|
| Platform | iOS |
| Target architecture | ARM64 |
| Environment | Linux |
| Execution | Native kernel + interpreted userspace |
| JIT dependency | None |
| Main language | Rust |
| Development assistance | Claude |
</aside>

## 01 / Why is this difficult?

iOS isn't exactly designed to be a general-purpose virtualization platform.

Apple imposes restrictions around executable memory, code signing, and dynamically generated machine code. This makes traditional JIT-based execution difficult without the appropriate entitlements.

On a normal Linux machine, you have considerably more freedom when it comes to memory permissions and executing dynamically generated code.

On iOS, you have to design around what the platform actually allows.

I didn't want the entire project to depend on obtaining special JIT entitlements, so I started looking into alternative execution models.

### The main restrictions

| Area | Problem |
|---|---|
| JIT compilation | Dynamically generated executable code is restricted |
| Code signing | Executable code must comply with Apple's signing requirements |
| Memory protection | Executable memory permissions are constrained |
| Virtualization | Hardware virtualization isn't generally available to ordinary iOS apps |
| Process isolation | The environment must operate within normal application boundaries |

The interesting part was figuring out how to build around these limitations rather than fighting them.

## 02 / The architecture

The biggest decision was separating kernel execution from userspace execution.

Instead of treating everything as one giant emulation problem, I used a hybrid execution model.

```text
                 iOS APPLICATION
                       |
             +---------+---------+
             |                   |
             v                   v
        Linux Kernel        Userspace Layer
          ARM64             Interpreter
             |                   |
             v                   v
       Native execution    Instruction decoding
             |                   |
             +---------+---------+
                       |
                       v
                 Host resources
                       |
                       v
                  iPhone hardware
```

### Component breakdown

| Component | Responsibility |
|---|---|
| Linux kernel | Core operating system functionality |
| ARM64 execution | Native instruction execution |
| Interpreter | Executes guest userspace instructions |
| Memory subsystem | Maintains guest execution memory |
| Host runtime | Connects execution to iOS resources |

This approach avoids having to emulate an entire physical computer while still providing an execution environment for Linux userspace.

## 03 / ARM64 and native execution

One advantage of targeting ARM64 is that modern iPhones already use ARM-based processors.

The kernel can therefore be built for the device's native instruction set.

This removes the need for traditional CPU instruction emulation at the kernel level.

A simplified comparison:

| Approach | Instruction handling |
|---|---|
| Full CPU emulation | Guest instructions are emulated |
| Dynamic translation | Guest instructions are translated into host code |
| Native ARM64 | Compatible instructions execute directly |

Native execution is particularly useful on mobile hardware, where avoiding unnecessary translation overhead can make a meaningful difference.

Of course, native execution doesn't automatically solve every compatibility issue. The runtime still needs to handle the interfaces and resources expected by the guest environment.

## 04 / Userspace without JIT

This is probably the most interesting part of the implementation.

Even if the kernel executes natively, userspace still needs a way to execute applications without depending on JIT compilation.

The solution is software interpretation.

An interpreter maintains the guest CPU state and processes instructions individually.

### Execution cycle

```text
       Fetch instruction
               |
               v
        Decode instruction
               |
               v
       Read guest registers
               |
               v
       Execute instruction
               |
               v
       Update CPU state
               |
               v
        Advance program counter
               |
               +-------> Repeat
```

A simplified example of what an execution loop might look like:

```rust
loop {
    let instruction = fetch_instruction(pc);
    let decoded = decode_instruction(instruction);

    execute_instruction(decoded, &mut cpu_state);

    pc = cpu_state.program_counter;
}
```

This is illustrative pseudocode rather than a complete implementation.

### What needs to be tracked?

| State | Purpose |
|---|---|
| Program counter | Tracks the next instruction |
| General registers | Stores guest CPU values |
| Stack pointer | Tracks the guest stack |
| Flags | Stores processor condition state |
| Memory state | Represents guest memory |
| Execution state | Tracks the current execution context |

The tricky part isn't simply decoding instructions. It's making sure every operation updates the guest state correctly.

A mistake in register handling, branching, or memory access can cause failures much further down the execution path.

## 05 / Memory management

Memory management deserves its own section because the guest and host environments have different expectations.

Linux expects to manage its own virtual address space, while the iOS application operates within the host process's memory constraints.

The implementation has to maintain a clear separation between the two.

### Important considerations

| Area | What needs to happen |
|---|---|
| Address translation | Resolve guest memory accesses |
| Allocation | Reserve memory for guest execution |
| Permissions | Validate memory access |
| Stack | Maintain guest stack state |
| Heap | Handle dynamic allocations |
| Alignment | Respect architecture requirements |
| Synchronization | Keep execution state consistent |

This becomes especially important when applications start doing more than basic operations.

Memory bugs can be particularly annoying because their symptoms aren't always immediate. An invalid access might cause a crash somewhere completely unrelated to the original problem.

## 06 / Native execution vs interpretation

One of the trade-offs with this architecture is performance.

Native execution and interpretation have very different characteristics.

| Characteristic | Native execution | Interpretation |
|---|---|---|
| Instruction handling | Direct CPU execution | Software decoding |
| Runtime overhead | Lower | Higher |
| JIT required | No | No |
| Compatibility | Architecture dependent | Depends on implemented instructions |
| Implementation complexity | Platform dependent | More interpreter logic |

The important thing is that avoiding JIT doesn't mean avoiding native execution entirely.

Different parts of the environment can use different execution strategies.

That's what makes this approach interesting.

## 07 / Development process

This project involved quite a bit of experimentation.

A lot of the time, getting one component working exposed problems somewhere else.

For example, an application failing to execute doesn't necessarily mean the instruction decoder is broken. It could be a memory issue, incorrect execution state, or an incompatibility somewhere in the runtime.

Having a way to inspect state and narrow down failures is extremely important when working at this level.

### Development workflow

```text
Implementation
      |
      v
Build / compile
      |
      v
Run on iOS
      |
      v
Inspect failures
      |
      v
Debug execution state
      |
      v
Adjust implementation
      |
      +------> Repeat
```

### A little help from Claude

I also used Claude throughout development.

It helped with understanding unfamiliar implementation details, exploring different approaches, investigating compiler errors, and working through debugging problems.

It definitely wasn't a case of sending one prompt and magically getting a working Linux environment.

There was a lot of back and forth, testing, and fixing things that didn't work.

Still, having an assistant available to reason through complicated low-level code made development considerably easier.

## 08 / Current limitations and future work

Getting the environment running is one thing. Making it practical for everyday use is another.

There are still plenty of areas I'd like to explore.

| Area | Future improvements |
|---|---|
| Performance | Reduce interpreter overhead |
| Compatibility | Support more userspace applications |
| Filesystem | Improve host and guest integration |
| Networking | Expand network functionality |
| Memory | Improve allocation and memory handling |
| Stability | Test longer and more complex workloads |

These are areas I'd like to continue working on, rather than claims that everything is already implemented.

## 09 / Final thoughts

I originally started this because I was curious about how far I could push iOS without JIT.

I ended up spending a lot of time working with ARM64, instruction execution, memory management, and the details involved in getting an operating system to run inside another operating system.

It's been a pretty interesting project, especially considering how restrictive the platform can be.

The main takeaway for me is that there are often more ways to approach a problem than the obvious ones.

And apparently, one of those ways is getting Linux running on an iPhone without JIT.

**More experiments coming soon.**

---

<small>Skylo · Founder of Kelly Inc. · November 12, 2026</small>
