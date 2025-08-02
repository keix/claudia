#!/bin/sh

# Run QEMU with RISC-V 64-bit virt machine
# Use OpenSBI but handle M-mode transition in software
qemu-system-riscv64 \
    -machine virt \
    -kernel zig-out/bin/kernel \
    -nographic \
    -d int,cpu_reset \
    -D logs/qemu.log
