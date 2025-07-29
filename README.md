# Claudia
**Claudia** is a minimal operating system written entirely in [Zig](https://ziglang.org/).  
It aims to teach systems programming without libc, without runtime, and without compromise.

This project contains:

- A Linux userland built with raw syscalls in Zig
- A freestanding RISC-V64 kernel, bootable with QEMU

If you want to understand how a system works, you must write one — under the POSIX.

## Why "Claudia"?
A quiet name for a quiet system.  
No noise. No frameworks. Just code and the machine beneath it.

## Requirements
- Linux (x86_64)
- Zig 0.14.0
- QEMU 8.0 or later
- NASM for bootloader assembly

## Philosophy
No libc.  
No runtime.  
No magic.  

This is a teaching OS. You write the code, you get the result. Nothing more.
Understand the system by building one.

## License
Copyright KEI SAWAMURA 2025 All rights reserved.  
Claudia is licensed under the MIT License. Copying, sharing, and modifying is encouraged and appreciated.