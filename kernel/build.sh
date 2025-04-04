#!/bin/bash

# Create output directory
mkdir -p bin

# Convert ELF to raw binary
objcopy -O binary zig-out/bin/kernel bin/kernel.bin

# Assemble the bootloader
nasm -f bin src/bootloader_32bit.asm -o bin/bootloader.bin

# Create OS image by concatenating bootloader and kernel
cat bin/bootloader.bin bin/kernel.bin > bin/os.img

echo "Build completed. OS image created at bin/os.img"
