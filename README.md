# Claudia

**Claudia** is a minimal, educational operating system written entirely in [Zig](https://ziglang.org/).  
It is designed to teach low-level systems programming and OS architecture without relying on libc or high-level abstractions.

This project includes both:

- A **userland** environment for Linux using raw system calls via Zig
- A **freestanding kernel** bootable with QEMU, built from scratch

---

## 🌖 Why "Claudia"?

The name *Claudia* evokes clarity, elegance, and a quiet sense of control.  
It represents the philosophy behind this project — clean design, deliberate choices, and a deep dive into the foundations of computing.

---

## 📦 Requirements

Note: 👉 While Zig uses LLVM internally, Claudia does not depend on any LLVM runtime or libraries at execution time.

- Linux (x86_64)
- [Zig](https://ziglang.org/) 0.14.0-dev or later
- QEMU 8.0 or later
- NASM (optional, for bootloader support)

Optional tools:

- `strace` – for debugging syscalls
- `gdb` – for low-level debugging

---

## 🧪 Tested With

- 🐧 **OS**: Gentoo Linux 6.6.32-gentoo-dist (x86_64)
- ⚙️ **CPU**: Intel Core i5-14600K
- ⚡ **Zig**: 0.14.0-dev.2178+bd7dda0c5
- 🖥️ **QEMU**: 8.2.3

---

## 🚀 Getting Started

### Userland (Linux syscall examples)

```bash
cd user/
zig build-exe main.zig -O ReleaseSmall
./main
```

To verify static linking:
```bash
ldd main                                                                                                                                                                                                                                                                      ─╯
# => not a dynamic executable
```

### Kernel (QEMU bootable)

```bash
./run.sh
```

Note: 👉 See `kernel/README.md` for details on the bootloader and linker setup.

---

## 📚 Philosophy
- No libc
- No runtime
- Just pure Zig and the metal

This project is not intended for production. It is a learning environment designed to give you a clear view of what your code actually does at the lowest level.  
The goal is to make the invisible visible — to understand, not just use.

---

## 🪐 License

Copyright KEI SAWAMURA 2025 All rights reserved.  
Claudia is licensed under the MIT License. Copying, sharing, and modifying is encouraged and appreciated.

