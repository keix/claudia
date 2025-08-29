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
| **Total System Calls** | ~48 | 18 implemented | 37.5% |
| **Process Control** | 12 | 6 implemented | 50.0% |
| **File Management** | 15 | 6 implemented | 40.0% |
| **Directory Operations** | 2 | 3 implemented | 150% |
| **Device Operations** | 6 | 0 implemented | 0% |
| **Time Operations** | 3 | 3 implemented | 100% |
| **Other System Operations** | 10 | 0 implemented | 0% |

### Detailed System Call Implementation Status

#### Process Control (6/12 implemented)
| System Call | V6 # | Claudia # | Status | Notes |
|-------------|------|-----------|--------|-------|
| **fork** | 2 | 220 (clone) | Implemented | Simplified version (no COW) |
| **exit** | 1 | 93 | Implemented | Basic cleanup only |
| wait | 2 | 260 (wait4) | - | No zombie handling |
| **exec** | 11 | 221 (execve) | Implemented | Hardcoded to shell only |
| **getpid** | 20 | 172 | Implemented | Returns current process ID |
| getuid | 24 | 174 | - | Single-user system |
| setuid | 23 | 146 | - | |
| nice | 34 | - | - | |
| kill | 37 | 129 | - | No signals |
| signal | 48 | 134 (rt_sigaction) | - | |
| alarm | 27 | - | - | |
| pause | 29 | - | - | |
| **clone** | - | 220 | Implemented | Simplified to fork() |
| **sched_yield** | - | 124 | Implemented | Modern addition |

#### File Management (6/15 implemented)
| System Call | V6 # | Claudia # | Status | Notes |
|-------------|------|-----------|--------|-------|
| **open** | 5 | 56 (openat) | Implemented | Via openat with AT_FDCWD |
| **close** | 6 | 57 | Implemented | |
| **read** | 3 | 63 | Implemented | Files and devices |
| **write** | 4 | 64 | Implemented | Files and devices |
| creat | 8 | - | - | Use open with flags |
| link | 9 | - | - | |
| unlink | 10 | 35 (unlinkat) | - | |
| **lseek** | 19 | 62 | Implemented | Modern lseek with SEEK_SET/CUR/END |
| **fstat** | 28 | 80 | Implemented | File status by file descriptor |
| stat | 18 | 79 (fstatat) | - | |
| chmod | 15 | - | - | |
| chown | 16 | - | - | |
| dup | 41 | - | - | |
| pipe | 42 | - | - | |
| access | - | - | - | Not in V6 |

#### Directory Operations (3/2 implemented - 150%)
| System Call | V6 # | Claudia # | Status | Notes |
|-------------|------|-----------|--------|-------|
| **chdir** | 12 | 49 | Implemented | Changes current working directory |
| mknod | 14 | - | - | |
| **readdir** | - | 61 (getdents64) | Implemented | Modern replacement for raw inode reading |
| **getcwd** | - | 17 | Implemented | Modern addition - not in V6 |
| mkdir | - | 34 (mkdirat) | - | Modern addition |

#### Device Operations (0/6 implemented)
| System Call | V6 # | Claudia # | Status | Notes |
|-------------|------|-----------|--------|-------|
| mount | 21 | - | - | |
| umount | 22 | - | - | |
| sync | 36 | - | - | |
| stty | 31 | - | - | |
| gtty | 32 | - | - | |
| ioctl | 54 | 29 | - | |

#### Time Operations (3/3 implemented - 100%)
| System Call | V6 # | Claudia # | Status | Notes |
|-------------|------|-----------|--------|-------|
| stime | 25 | - | - | Use clock_settime instead |
| **time** | 13 | 1062 | Implemented | Returns seconds since epoch |
| times | 43 | - | - | Process times not tracked |
| **clock_gettime** | - | 113 | Implemented | Modern high-precision time |
| **nanosleep** | - | 101 | Implemented | Modern sleep with nanosecond precision |

#### System Operations (0/10 implemented)
| System Call | V6 # | Claudia # | Status | Notes |
|-------------|------|-----------|--------|-------|
| break/sbrk | 17 | 214 (brk) | - | Heap management exists |
| prof | 44 | - | - | |
| setgid | 46 | - | - | |
| getgid | 47 | 176 | - | |
| acct | 51 | - | - | |
| phys | 52 | - | - | Not applicable to RISC-V |
| lock | 53 | - | - | |
| mpx | 56 | - | - | |
| ptrace | 26 | - | - | |
| umask | - | - | - | Not in V6 |

### Implementation Priority

Based on current needs for shell and Lisp interpreter:

1. **Immediate Priority**
   - `stat` - File information for `ls -l` (fstat done)
   - `creat` - Explicit file creation
   
2. **High Priority**
   - `wait` - Process synchronization (fork/exec done)
   - `pipe` - Inter-process communication
   
3. **Medium Priority**
   - `signal/kill` - Process control
   - `link/unlink` - File management
   - `chmod/chown` - Permissions

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
- Basic arithmetic operations (+, -, *, /, mod, =, <=, >)
- String literals with escape sequences and concatenation
- Boolean operations and conditionals (if, and, or, cond)
- Variable definitions (define) and mutation (set)
- Function definitions (defun, lambda)
- Quote and eval
- File loading (load)
- System calls (syscall)
- Looping constructs (while)
- Comments (;)

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
| **Lines of Code** | ~9,000 | ~12,000 (+ assembly, lisp) |
| **Build System** | make | Zig build system |
| **Initrd Tool** | None | mkinitrd.zig |

### Development Advantages
- Modern systems language with safety features
- Integrated toolchain and build system
- No dependency on C standard library
- Clean, maintainable codebase

## Current Status

Claudia has achieved:
- Basic kernel with memory management
- Process creation and scheduling
- Simple filesystem with initrd
- Basic shell and utilities
- Device abstraction layer
- Interrupt handling
- Educational Lisp interpreter with functions

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
