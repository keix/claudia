#!/bin/sh

# Run QEMU with RISC-V 64-bit virt machine
# OpenSBI runs in M-mode and starts our kernel in S-mode
qemu-system-riscv64 \
    -machine virt \
    -kernel zig-out/bin/kernel \
    -nographic \
    -d int,cpu_reset \
    -D logs/qemu.log
