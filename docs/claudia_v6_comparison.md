# Claudia vs UNIX Sixth Edition Comparison

## Overview

Claudia is a modern rewrite of UNIX Sixth Edition, implemented in Zig for the RISC-V architecture. While maintaining the simplicity and elegance of V6's design philosophy, Claudia leverages modern hardware capabilities and programming practices.

## Architecture

| Feature | UNIX V6 | Claudia |
|---------|---------|---------|
| **CPU Architecture** | PDP-11 (16-bit) | RISC-V RV64 (64-bit) |
| **MMU Support** | None | Sv39 (3-level page tables) |
| **Address Space** | Physical only | Full virtual memory |

## Memory Management

| Feature | UNIX V6 | Claudia |
|---------|---------|---------|
| **Virtual Memory** | None, physical only | Full paging with Sv39 |
| **Memory Size** | Max 256KB | Up to 512GB virtual (256MB physical) |
| **Protection** | Basic segment bounds | Per-page R/W/X bits |
| **Swapping** | Whole process swap | Planned per-page swap |
| **Heap Management** | brk/sbrk syscalls | sbrk implemented |

### Key Improvements
- Hardware-enforced memory protection
- Modern 64-bit address space
- Efficient page-based memory management

## Process Management

| Feature | UNIX V6 | Claudia |
|---------|---------|---------|
| **Max Processes** | 50 | 64 (configurable) |
| **Scheduling** | Round-robin | Simple round-robin |
| **Context Switch** | Assembly routines | RISC-V context switch |
| **Process States** | SSLEEP, SRUN, etc. | SLEEPING, RUNNABLE, etc. |

### Implementation Status
- Basic process creation and switching works
- No copy-on-write for fork() yet
- Simple scheduler without priorities

## System Calls

| System Call | UNIX V6 | Claudia | Notes |
|-------------|---------|---------|-------|
| **Total Count** | ~48 | 8 implemented | Gradual implementation |
| **fork()** | Full implementation | Simplified (no COW) | Copy-on-write planned |
| **exec()** | Loads a.out format | ELF loader | Modern executable format |
| **read/write** | Blocking I/O | Blocking I/O | Same semantics |
| **open/close** | Full filesystem | Basic implementation | /dev/ramdisk supported |
| **exit()** | Process cleanup | Basic implementation | No zombie reaping yet |
| **wait()** | Parent-child sync | Not implemented | Planned |
| **sbrk()** | Memory allocation | Implemented | Heap management works |

## File System

| Feature | UNIX V6 | Claudia |
|---------|---------|---------|
| **Type** | Simple FS (s5fs) | SimpleFS on RAM disk |
| **Inodes** | 16-byte inodes | FileEntry struct (64 bytes) |
| **Block Size** | 512 bytes | 512 bytes |
| **Special Files** | /dev/tty, etc. | /dev/console, /dev/ramdisk |
| **Directories** | Linear search | Hierarchical support |
| **Initrd** | None | Embedded initrd |
| **Max Files** | Unlimited | 16 files (configurable) |

### SimpleFS Features
- Basic file storage with directories
- Files loaded from initrd at boot
- Full path traversal support
- Device abstraction for console and ramdisk

## Device Drivers

| Component | UNIX V6 | Claudia |
|-----------|---------|---------|
| **TTY Driver** | Full termios | Basic canonical mode |
| **Disk Driver** | RK05, RP04 | RAM disk (128KB) |
| **Console** | KL11 serial | UART 16550 |

### Driver Features
- Line editing works in canonical mode
- QEMU virtual device support
- In-memory storage via ramdisk

## Interrupt Handling

| Feature | UNIX V6 | Claudia |
|---------|---------|---------|
| **Timer** | 60Hz clock | 10MHz (configurable) |
| **Device IRQs** | Direct handling | PLIC controller |
| **Trap Handling** | Assembly traps | RISC-V trap handler |

### Modern Improvements
- RISC-V timer with high precision
- Modern interrupt routing via PLIC
- Hardware-assisted trap handling

## Boot Process

| Component | UNIX V6 | Claudia |
|-----------|---------|---------|
| **Bootloader** | Stand-alone boot | OpenSBI + kernel |
| **Init Process** | /etc/init | /sbin/init |
| **Multi-user** | getty + login | Single-user only |

### Boot Sequence
1. OpenSBI initializes hardware
2. Kernel loads with embedded initrd
3. SimpleFS mounts initrd contents
4. Init process starts shell

## Userland Tools

| Category | UNIX V6 | Claudia |
|----------|---------|---------|
| **Shell** | Bourne shell (sh) | Minimal shell |
| **Core Utils** | ls, cat, ed, etc. | ls, cat, echo, help, exit |
| **Lisp Interpreter** | None | Minimal Lisp with strings |
| **Compiler** | cc (C compiler) | Cross-compiled only |
| **Assembler** | as | Zig handles assembly |

### Lisp Features
- Basic arithmetic operations (+, -, *, /, mod)
- String literals and concatenation
- Boolean operations and conditionals
- Variable definitions
- Quote and eval

## IPC & Signals

| Feature | UNIX V6 | Claudia |
|---------|---------|---------|
| **Signals** | Full signal system | Not implemented |
| **Pipes** | Anonymous pipes | Planned |
| **Shared Memory** | None | Modern IPC planned |

## Security

| Feature | UNIX V6 | Claudia |
|---------|---------|---------|
| **Users/Groups** | UID/GID system | Single-user currently |
| **Permissions** | rwxrwxrwx | Will use modern ACLs |
| **Root** | Superuser (UID 0) | Capability-based planned |

## Development

| Aspect | UNIX V6 | Claudia |
|--------|---------|---------|
| **Language** | C (K&R) | Zig (100% no libc) |
| **Lines of Code** | ~9,000 | ~10,000 (9,792 .zig + assembly) |
| **Build System** | make | Zig build system |
| **Initrd Tool** | None | mkinitrd.zig |

### Development Advantages
- Modern systems language with safety features
- Integrated toolchain and build system
- No dependency on C standard library
- Clean, maintainable codebase

## Current Status

Claudia has achieved:
- ✅ Basic kernel with memory management
- ✅ Process creation and scheduling
- ✅ Simple filesystem with initrd
- ✅ Basic shell and utilities
- ✅ Device abstraction layer
- ✅ Interrupt handling
- ✅ Educational Lisp interpreter

## Future Plans

1. **Short Term**
   - Implement remaining core system calls
   - Add pipe support
   - Improve filesystem (subdirectories, permissions)
   
2. **Medium Term**
   - Signal system
   - Copy-on-write fork
   - Network stack
   - More userland tools
   
3. **Long Term**
   - Multi-user support
   - Modern security model
   - Full POSIX compatibility
   - Self-hosting development

## Conclusion

While Claudia already exceeds UNIX V6 in code size (~10,000 lines vs ~9,000), this reflects the complexity of modern hardware and the additional safety guarantees provided by Zig. The project successfully demonstrates that V6's elegant design principles can be adapted to modern 64-bit RISC-V systems while maintaining conceptual simplicity.

The use of Zig as the implementation language provides memory safety without garbage collection, making it ideal for systems programming. The 100% libc-free implementation ensures complete control over the system's behavior and dependencies.