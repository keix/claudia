# Claudia
**Claudia** is a minimal operating system written entirely in [Zig](https://ziglang.org/).  
It aims to teach systems programming without libc, without runtime, and without compromise.

This project contains:

- A Linux userland built with raw system calls in Zig
- A freestanding RISC-V64 kernel, designed to run on bare metal

If you want to understand how a system works, you must write one — under the POSIX.

## Why "Claudia"?
A quiet name for a quiet system.  
No noise. No frameworks. Just code and the machine beneath it.

## Requirements
Zig is the only requirement.  
You can build and run Claudia with the Zig compiler version 0.14.0, available at [ziglang.org](https://ziglang.org/download/).

Claudia depends on no operating system, no runtime, and no external libraries.
It builds a system — from first principles, not from dependencies.

You may run it on QEMU, or on real hardware.
That's an implementation detail.

## Philosophy
A system is just structure. POSIX is the sugar that coats it.

Claudia doesn't hide the machine — it reveals it.  
There is no runtime, no libc, no illusion. Only instructions, traps, and agreements.

What you see is what the hardware sees.  
POSIX is not the system — but a contract you implement to make it human.

To understand it, you must write it.

## License
Copyright KEI SAWAMURA 2025 All rights reserved.  
Claudia is licensed under the MIT License. Copying, sharing, and modifying is encouraged and appreciated.
