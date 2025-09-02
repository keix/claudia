# Claudia vs UNIX Sixth Edition Comparison

## Overview

Claudia is a modern rewrite of UNIX Sixth Edition, implemented in Zig for the RISC-V architecture. While maintaining the simplicity and elegance of V6's design philosophy, Claudia leverages modern hardware capabilities and programming practices.

## Architecture

| Feature | UNIX V6 | Claudia |
|---------|---------|---------|
| **CPU Architecture** | PDP-11 (16-bit) | RISC-V RV64 (64-bit) |
| **MMU Support** | Segmentation (PDP-11/45, 11/70) | Sv39 (3-level page tables) |
| **Address Space** | Segmented (I/D split) | Full virtual memory |

## Memory Management

| Feature | UNIX V6 | Claudia |
|---------|---------|---------|
| **Virtual Memory** | Segmentation-based | Full paging with Sv39 |
| **Memory Size** | 64KB per process | Up to 512GB virtual (256MB physical) |
| **Protection** | Segment-based R/W/E | Per-page R/W/X bits |
| **Swapping** | Whole process swap | Planned per-page swap |
| **Heap Management** | brk/sbrk syscalls | sbrk implemented |

### Key Improvements
- Hardware-enforced memory protection
- Modern 64-bit address space
- Efficient page-based memory management

Note: UNIX V6 did support memory management on PDP-11/45 and 11/70 models with segmentation hardware. Each process could use up to 64KB of memory divided into 8KB segments, with separate instruction and data spaces (I/D split) on capable models.

## Process Management

| Feature | UNIX V6 | Claudia |
|---------|---------|---------|
| **Max Processes** | 50 | 64 (configurable) |
| **Scheduling** | Round-robin | Round-robin with idle process |
| **Context Switch** | Assembly routines | RISC-V context switch |
| **Process States** | SSLEEP, SRUN, etc. | SLEEPING, RUNNABLE, etc. |

### Implementation Status
- Process creation with fork() and exec() working
- Fork with memory isolation (independent page tables)
- wait() system call for process synchronization
- Zombie process reaping
- Context switching with proper privilege mode handling
- Idle process prevents scheduler panic
- Simple round-robin scheduler without priorities

## System Calls

### Summary

| Category | UNIX V6 | Claudia | Implementation Rate |
|----------|---------|---------|-------------------|
| **Total System Calls** | 41 | 29 implemented | 70.7% |
| **Process Control** | 11 | 10 implemented | 90.9% |
| **File Management** | 14 | 10 implemented | 71.4% |
| **Directory Operations** | 2 | 4 implemented | 200% |
| **Device Operations** | 5 | 0 implemented | 0% |
| **Time Operations** | 3 | 3 implemented | 100% |
| **Other System Operations** | 4 | 2 implemented | 50% |

### Detailed System Call Implementation Status

#### Process Control (10/11 implemented)
| System Call | V6 # | Claudia # | Status | Notes |
|-------------|------|-----------|--------|-------|
| **fork** | 2 | 220 (clone) | Implemented | Memory isolation with independent page tables |
| **exit** | 1 | 93 | Implemented | Cleans up resources and wakes parent |
| **wait** | 7 | 260 (wait4) | Implemented | Basic zombie reaping |
| **exec** | 11 | 221 (execve) | Implemented | Hardcoded to shell only |
| **getpid** | 20 | 172 | Implemented | Returns current process ID |
| **getppid** | - | 110 | Implemented | Returns parent process ID |
| **getuid** | 24 | 174 | Implemented | Always returns 0 (root) |
| **setuid** | 23 | 146 | Implemented | No-op in single-user system |
| nice | 34 | - | - | |
| kill | 37 | 129 | - | No signals |
| signal | 48 | 134 (rt_sigaction) | - | |
| ptrace | 26 | - | - | Process debugging |
| **clone** | - | 220 | Implemented | Simplified to fork() |
| **sched_yield** | - | 124 | Implemented | Modern addition |

#### File Management (10/14 implemented)
| System Call | V6 # | Claudia # | Status | Notes |
|-------------|------|-----------|--------|-------|
| **openat** | - | 56 | Implemented | Modern open with directory support |
| **close** | 6 | 57 | Implemented | |
| **read** | 3 | 63 | Implemented | Files and devices |
| **write** | 4 | 64 | Implemented | Files and devices |
| creat | 8 | - | - | Use open with flags |
| link | 9 | - | - | |
| **unlink** | 10 | 35 (unlinkat) | Implemented | Modern unlinkat with AT_FDCWD |
| **lseek** | 19 | 62 | Implemented | Modern lseek with SEEK_SET/CUR/END |
| **fstat** | 28 | 80 | Implemented | File status by file descriptor |
| stat | 18 | 79 (fstatat) | - | |
| chmod | 15 | - | - | |
| chown | 16 | - | - | |
| **dup** | 41 | 23 | Implemented | Duplicate file descriptor |
| **dup2** | - | 24 (dup3) | Implemented | Modern dup2 via dup3 |
| pipe | 42 | - | - | |
| open | 5 | - | - | Use openat instead |

#### Directory Operations (4/2 implemented - 200%)
| System Call | V6 # | Claudia # | Status | Notes |
|-------------|------|-----------|--------|-------|
| **chdir** | 12 | 49 | Implemented | Changes current working directory |
| mknod | 14 | - | - | |
| **getdents64** | - | 61 | Implemented | Modern Linux-style directory reading |
| **getcwd** | - | 17 | Implemented | Modern addition - not in V6 |
| **mkdirat** | - | 34 | Implemented | Modern addition with AT_FDCWD support |
| **unlinkat** | - | 35 | Implemented | Modern addition for file/directory removal |

#### Device Operations (0/5 implemented)
| System Call | V6 # | Claudia # | Status | Notes |
|-------------|------|-----------|--------|-------|
| mount | 21 | - | - | |
| umount | 22 | - | - | |
| sync | 36 | - | - | |
| stty | 31 | - | - | |
| gtty | 32 | - | - | |

#### Time Operations (3/3 implemented - 100%)
| System Call | V6 # | Claudia # | Status | Notes |
|-------------|------|-----------|--------|-------|
| stime | 25 | - | - | Use clock_settime instead |
| **time** | 13 | 1062 | Implemented | Returns seconds since epoch |
| times | 43 | - | - | Process times not tracked |
| **clock_gettime** | - | 113 | Implemented | Modern high-precision time |
| **nanosleep** | - | 101 | Implemented | Modern sleep with nanosecond precision |

#### System Operations (2/4 implemented)
| System Call | V6 # | Claudia # | Status | Notes |
|-------------|------|-----------|--------|-------|
| break/sbrk | 17 | 214 (brk) | - | Heap management exists |
| **setgid** | 46 | 144 | Implemented | No-op in single-user system |
| **getgid** | 47 | 176 | Implemented | Always returns 0 (root) |
| profil | 44 | - | - | Execution profiling |

### Implementation Priority

Based on current needs for shell and Lisp interpreter:

1. **Immediate Priority**
   - `stat` - File information for `ls -l` (fstat done)
   - `creat` - Explicit file creation
   
2. **High Priority**
   - `pipe` - Inter-process communication
   - `signal/kill` - Process control
   
3. **Medium Priority**
   - `signal/kill` - Process control
   - `link` - Hard links (unlink done)
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
| **Core Utils** | ls, cat, ed, etc. | [Claudia commands utilities](docs/claudia_commands_utilities.md) |
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
| **Lines of Code** | ~9,000 | ~14,000 (kernel + userland + assembly) |
| **Build System** | make | Zig build system |
| **Initrd Tool** | None | mkinitrd.zig |

### Development Advantages
- Modern systems language with safety features
- Integrated toolchain and build system
- No dependency on C standard library
- Clean, maintainable codebase

## Current Status

Claudia has achieved:
- Kernel with paging-based memory management (Sv39)
- Working multiprocess support with fork() and exec()
- Fork with memory isolation (independent page tables for each process)
- Process synchronization with wait() system call
- Zombie process reaping
- Context switching with proper privilege mode transitions
- Idle process prevents scheduler deadlock
- Simple filesystem with initrd
- Basic shell and utilities (ls, cat, echo, pwd, cd, mkdir, rm, touch, date, id, sleep)
- Directory operations (Linux-style openat + getdents64)
- File removal (unlinkat system call)
- Device abstraction layer
- UART interrupt handling with PLIC
- Educational Lisp interpreter with functions
- High-precision time support (10MHz timer)
- Sleep functionality with nanosleep system call

## Future Plans

1. **Short Term**
   - Implement stat/fstatat for file information
   - Add pipe support
   - INode/VNode unification
   - File permissions and ownership
   - Copy-on-write fork optimization
   
2. **Medium Term**
   - Signal system
   - Network stack
   - More userland tools
   - Multi-user support
   
3. **Long Term**
   - Multi-user support
   - Modern security model
   - Full POSIX compatibility
   - Self-hosting development

## Conclusion

While Claudia exceeds UNIX V6 in code size (~14,000 lines vs ~9,000), this reflects the complexity of modern hardware and the additional safety guarantees provided by Zig. The project successfully demonstrates that V6's elegant design principles can be adapted to modern 64-bit RISC-V systems while maintaining conceptual simplicity.

The use of Zig as the implementation language provides memory safety without garbage collection, making it ideal for systems programming. The 100% libc-free implementation ensures complete control over the system's behavior and dependencies.
