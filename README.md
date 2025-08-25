# Claudia — A Rewrite of UNIX Sixth Edition
For a crystal-clear understanding of the system’s structure, start here.

This project reimagines UNIX Sixth Edition  
Rewritten in Zig with modern clarity and minimalism on the [RISC-V](https://github.com/riscv/riscv-isa-manual/tree/main) architecture.

If you want to understand how a system works, you must write one — under the POSIX.

## Why Claudia
A quiet name for a quiet system.  

## Specification
In the spirit of UNIX, the specification is simple.  
Everything else emerges from these foundations.

You deserve Lisp. And I, Zig.

- An experimental Lisp extension
- The core implementation of UNIX Sixth Edition  

[Claudia Design Spec — v6-inspired OS in Zig on RISC-V](https://v6-unix.notion.site/25ab8ecae494815ba362d80c0a11cb83?v=25ab8ecae49481ff826a000c72a7926b4)


## Requirements
Zig is the only requirement.  
You can build and run Claudia with the Zig compiler version 0.14.1, available at [ziglang.org](https://ziglang.org/download/).

Claudia depends on no operating system, no runtime, and no external libraries.
It builds a system — from first principles, not from dependencies.

You may run it on QEMU, or on real hardware.
That's an implementation detail.

## Quick Start
You can build and run Claudia with a single command:

```
zig build run
```

This will:
- Build the kernel and userland
- Launch the system in QEMU

## Philosophy
A system is just structure. POSIX is the sugar that coats it.

Claudia doesn't hide the machine — it reveals it.  
What you see is what the hardware sees.  
POSIX is not the system — but a contract you implement to make it human.

## Acknowledgements
Claudia is built in the shadow of giants — with gratitude to Ken Thompson and Dennis Ritchie, whose creation of UNIX continues to shape everything we build.

## License
Copyright KEI SAWAMURA 2025 All rights reserved.  
Claudia is licensed under the MIT License. Copying, sharing, and modifying is encouraged and appreciated.
