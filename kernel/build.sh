#!/bin/bash

# ディレクトリの作成
mkdir -p bin

# ELFからバイナリへ変換
objcopy -O binary zig-out/bin/kernel bin/kernel.bin

# ブートローダーのアセンブル
nasm -f bin src/bootloader_32bit.asm -o bin/bootloader.bin

# OSイメージの作成
cat bin/bootloader.bin bin/kernel.bin > bin/os.img

echo "Build completed. OS image created at bin/os.img"
