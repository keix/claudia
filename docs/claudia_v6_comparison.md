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

### Summary

| Category | UNIX V6 | Claudia | Implementation Rate |
|----------|---------|---------|-------------------|
| **Total System Calls** | ~48 | 6 fully implemented | 12.5% |
| **Process Control** | 12 | 1 implemented | 8.3% |
| **File Management** | 15 | 4 implemented | 26.7% |
| **Directory Operations** | 2 | 1 implemented | 50% |
| **Device Operations** | 6 | 0 implemented | 0% |
| **Time Operations** | 3 | 0 implemented | 0% |
| **Other System Operations** | 10 | 0 implemented | 0% |

### Detailed System Call Implementation Status

#### Process Control (1/12 implemented)
| System Call | V6 # | Claudia Status | Notes |
|-------------|------|----------------|-------|
| fork | 2 | Not implemented | Simplified version planned |
| **exit** | 1 | Implemented | Basic cleanup only |
| wait | 2 | Not implemented | No zombie handling |
| exec | 11 | Not implemented | ELF loader exists |
| getpid | 20 | Not implemented | |
| getuid | 24 | Not implemented | Single-user system |
| setuid | 23 | Not implemented | |
| nice | 34 | Not implemented | |
| kill | 37 | Not implemented | No signals |
| signal | 48 | Not implemented | |
| alarm | 27 | Not implemented | |
| pause | 29 | Not implemented | |

#### File Management (4/15 implemented)
| System Call | V6 # | Claudia Status | Notes |
|-------------|------|----------------|-------|
| **open** | 5 | Implemented | Basic file/device support |
| **close** | 6 | Implemented | |
| **read** | 3 | Implemented | Files and devices |
| **write** | 4 | Implemented | Files and devices |
| creat | 8 | Not implemented | Use open with flags |
| link | 9 | Not implemented | |
| unlink | 10 | Not implemented | |
| seek | 19 | Not implemented | |
| fstat | 28 | Not implemented | |
| stat | 18 | Not implemented | |
| chmod | 15 | Not implemented | |
| chown | 16 | Not implemented | |
| dup | 41 | Not implemented | |
| pipe | 42 | Not implemented | |
| access | - | Not implemented | Not in V6 |

#### Directory Operations (1/2 implemented)
| System Call | V6 # | Claudia Status | Notes |
|-------------|------|----------------|-------|
| chdir | 12 | Not implemented | Logic exists |
| mknod | 14 | Not implemented | |
| **readdir** | - | Implemented | Modern replacement for raw inode reading |

#### Device Operations (0/6 implemented)
| System Call | V6 # | Claudia Status | Notes |
|-------------|------|----------------|-------|
| mount | 21 | Not implemented | |
| umount | 22 | Not implemented | |
| sync | 36 | Not implemented | |
| stty | 31 | Not implemented | |
| gtty | 32 | Not implemented | |
| ioctl | 54 | Not implemented | |

#### Time Operations (0/3 implemented)
| System Call | V6 # | Claudia Status | Notes |
|-------------|------|----------------|-------|
| stime | 25 | Not implemented | |
| time | 13 | Not implemented | |
| times | 43 | Not implemented | |

#### System Operations (0/10 implemented)
| System Call | V6 # | Claudia Status | Notes |
|-------------|------|----------------|-------|
| break/sbrk | 17 | Not implemented | Heap management exists |
| prof | 44 | Not implemented | |
| setgid | 46 | Not implemented | |
| getgid | 47 | Not implemented | |
| acct | 51 | Not implemented | |
| phys | 52 | Not implemented | Not applicable to RISC-V |
| lock | 53 | Not implemented | |
| mpx | 56 | Not implemented | |
| ptrace | 26 | Not implemented | |
| umask | - | Not implemented | Not in V6 |

### Implementation Priority

Based on current needs for shell and Lisp interpreter:

1. **Immediate Priority**
   - `seek` - File positioning needed for editors
   - `stat/fstat` - File information for `ls -l`
   - `creat` - Explicit file creation
   
2. **High Priority**
   - `fork/exec` - Process creation for proper shell
   - `wait` - Process synchronization
   - `pipe` - Inter-process communication
   
3. **Medium Priority**
   - `chdir` - Directory navigation
   - `time` - Timestamps
   - `signal/kill` - Process control

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
| **Lines of Code** | ~9,000 | ~10,000 (+ assembly) |
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
