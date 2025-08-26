# Claudia Source Code Reading Guide

This guide provides a step-by-step approach to understanding Claudia source code structure and implementation.

## 1. Project Structure Overview

Claudia consists of the following main components:

```
claudia/
├── abi/          - Common definitions between kernel and userland
├── docs/         - Here
├── kernel/       - Kernel core implementation
├── userland/     - Userland programs (init, shell)
├── rootfs/       - Root filesystem template
└── build.zig     - Build system configuration
```

## 2. Understanding the Boot Process (Recommended Reading Order)

### 2.1 Entry Points
1. `kernel/arch/riscv/entry.S` - First assembly code executed by CPU
   - Stack initialization
   - BSS section clearing
   - Boot parameter preservation (hartid, DTB, initrd)

2. `kernel/init.zig` - Zig code entry point
   - `start()` function called from assembly

3. `kernel/core.zig` - Kernel initialization center
   - Executes 5 initialization phases sequentially

### 2.2 Initialization Phases Detail

#### Phase 1: Early Boot
- `driver/uart/core.zig` - Serial console initialization
- `memory/core.zig` - Physical memory initialization

#### Phase 2: Memory System
- `memory/physical.zig` - Physical memory management
- `memory/virtual.zig` - Virtual memory management
- `memory/kalloc.zig` - Kernel heap allocator

#### Phase 3: Core Subsystems
- `file/core.zig` - File descriptor table
- `fs/vfs.zig` - Virtual file system
- `driver/ramdisk.zig` - RAM disk driver
- `boot/initrd.zig` - initrd loader

#### Phase 4: Process Management
- `process/core.zig` - Process management and scheduler
- `user/elf.zig` - ELF loader
- `user/memory.zig` - User space memory management

#### Phase 5: System Startup
- `trap/core.zig` - Trap handler (interrupts, exceptions, system calls)
- `syscalls/dispatch.zig` - System call dispatcher

## 3. Main Components Explanation

### Memory Management (memory/)
- **physical.zig**: 4KB page-based physical memory management
- **virtual.zig**: Page table management and mapping
- **allocator.zig**: Generic allocator interface
- **kalloc.zig**: Kernel heap implementation

### Process Management (process/)
- **core.zig**: Process structure, scheduler, context switching
- Process table, run queue, scheduling algorithm

### File System (fs/, file/)
- **vfs.zig**: Unified file system interface
- **simplefs.zig**: Simple file system implementation
- **memfs.zig**: Memory-based file system
- **inode.zig**: inode-based file management

### System Calls (syscalls/)
- **dispatch.zig**: System call number to handler mapping
- **fs.zig**: File system related (open, read, write, close)
- **process.zig**: Process related (exit, yield)
- **dir.zig**: Directory operations (readdir)

## 4. Userland Programs

### init Program (userland/sbin/init.zig)
- First process started by kernel
- Responsible for launching shell

### Shell (userland/bin/shell.zig, userland/shell/)
- Command line interface
- Built-in commands:
  - echo, help, exit, ls, cat, lisp
- Command registration in `commands/index.zig`

### System Call Wrappers (userland/syscalls/)
- Userland-side implementation for calling kernel system calls

## 5. Understanding the Build System

Important points in `build.zig`:

1. **Build Order**: Userland → Kernel
   - Kernel needs to embed userland binaries

2. **Binary Embedding**:
   - init and shell embedded into kernel via .S files
   - initrd embedded similarly

3. **Module Structure**:
   - ABI module for common definitions
   - syscall module for userland

## 6. Running

### Running with QEMU
```bash
zig build run
```

## 7. Next Steps

1. **Trap Handling**: Read `trap/core.zig`, `arch/riscv/trap.S` to understand system call implementation
2. **Context Switching**: Study `arch/riscv/context.S` for process switching
3. **User Mode Transition**: Examine `arch/riscv/umode.S` for kernel/user mode switching
4. **File System Implementation**: Deep dive into SimpleFS implementation

Following this guide will help you understand the overall architecture of Claudia and the role of each component.