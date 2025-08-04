#!/bin/sh
# This file is closer to documentation than a script.
# It serves as a clear entrypoint, wrapping Zig and QEMU commands
# with minimal sugar for building and running Claudia.
#
# Read it — and you’ll understand exactly how to build the system.

set -e

# Run QEMU with RISC-V 64-bit virt machine
# OpenSBI runs in M-mode and starts our kernel in S-mode
if [ ! -f "zig-out/bin/kernel" ]; then
    zig build
fi
if [ ! -d "logs" ]; then
    mkdir logs
fi
qemu-system-riscv64 \
    -machine virt \
    -kernel zig-out/bin/kernel \
    -nographic \
    -d int,cpu_reset \
    -D logs/qemu.log
