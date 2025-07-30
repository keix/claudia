# Claudia
**Claudia** is a minimal operating system written entirely in [Zig](https://ziglang.org/).  
It aims to teach systems programming without libc, without runtime, and without compromise.

This project contains:

- A Linux userland built with raw system calls
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
What you see is what the hardware sees.  
POSIX is not the system — but a contract you implement to make it human.

## Acknowledgements
Claudia is an independent system.

However, I would like to acknowledge the [Debian project](https://www.debian.org/), whose sid-based initrd (rebuilt for our purposes) was temporarily used to test RISC-V binary execution in the early stages of development.

And I was inspired by the elegance of [xv6-riscv](https://pdos.csail.mit.edu/6.1810/2024/xv6.html), a clean and minimal RISC-V operating system developed by MIT — A Sixth Edition of UNIX, rewritten for the next architecture.

## License
Copyright KEI SAWAMURA 2025 All rights reserved.  
Claudia is licensed under the MIT License. Copying, sharing, and modifying is encouraged and appreciated.
