# Claudia Architecture Document

## Table of Contents

1. [System Overview](#system-overview)
2. [Boot Process](#boot-process)
3. [Memory Management](#memory-management)
4. [Process Management](#process-management)
5. [Virtual File System](#virtual-file-system)
6. [System Call Interface](#system-call-interface)
7. [Interrupt and Trap Handling](#interrupt-and-trap-handling)
8. [Device Drivers](#device-drivers)
9. [User-Kernel Boundary](#user-kernel-boundary)
10. [Security Model](#security-model)

## System Overview

Claudia is a modern rewrite of UNIX Sixth Edition for RISC-V 64-bit architecture. The design philosophy emphasizes simplicity, clarity, and educational value while maintaining practical functionality.

### Design Principles

1. **Simplicity First**: Every component should be understandable
2. **No Hidden Magic**: Explicit over implicit behavior
3. **Static Where Possible**: Predictable memory usage
4. **Modern Safety**: Leverage Zig's safety features

### System Architecture Layers

```
+------------------+------------------+------------------+
|    Userland      |     Shell        |   Applications   |
+------------------+------------------+------------------+
|                  System Call Interface                 |
+--------------------------------------------------------+
|    Process       |      VFS         |      Memory      |
|   Management     |                  |    Management    |
+------------------+------------------+------------------+
|                    Trap Handler                        |
+--------------------------------------------------------+
|   UART Driver    |   PLIC Driver    |   Timer Driver   |
+------------------+------------------+------------------+
|              Hardware Abstraction Layer                |
+--------------------------------------------------------+
|                  RISC-V Hardware                       |
+--------------------------------------------------------+
```

## Boot Process

### Boot Sequence

1. **Hardware Reset** (0x80000000)
   - CPU starts at reset vector
   - All harts begin execution
   - Only hart 0 proceeds, others spin

2. **Assembly Entry** (`kernel/arch/riscv/entry.S`)
   ```assembly
   _start:
     # Set stack pointer to _stack_top
     la sp, _stack_top
     # Save boot parameters (hartid, dtb, initrd)
     # Clear BSS section
     # Set up global pointer
     # Jump to kinit
   ```

3. **Early Initialization** (`kernel/init.zig`)
   ```
   kinit:
     - Save device tree pointer
     - Call core.init()
   ```

4. **Core Initialization** (`kernel/core.zig`)
   ```
   Phase 1: Early Boot
     - Initialize UART (console output)
     - Initialize physical memory allocator
   
   Phase 2: Memory System
     - Initialize virtual memory structures
     - Initialize kernel heap (kalloc)
     - Enable MMU with kernel page table
   
   Phase 3: Subsystems
     - Initialize file system structures
     - Initialize VFS
     - Mount RAM disk
     - Load initrd (if present)
     - Initialize trap handlers
     - Enable interrupts
     - Initialize process scheduler
   
   Phase 4: User Mode
     - Create init process (PID 1)
     - Load embedded init binary
     - Start scheduler
   ```

### Memory Layout at Boot

```
0x80000000: +-----------------+
            |   Kernel Text   |
            +-----------------+
            |   Kernel Data   |
            +-----------------+
            |   Kernel BSS    |
            +-----------------+
            |  Boot Stacks    | (4KB per hart)
            +-----------------+
            |   Free Memory   |
            |  (for physmem)  |
0x88000000: +-----------------+
```

## Memory Management

### Physical Memory

Physical memory is managed by a simple free list allocator with 4KB pages.

#### Data Structures

```zig
// kernel/memory/physical.zig
pub const FrameAllocator = struct {
    bitmap: []u8,
    total_frames: usize,
    free_frames: usize,
    base_addr: usize,
};
```

#### Allocation Algorithm

1. **Initialization**: Set up bitmap where 1 = used, 0 = free
2. **Allocation**: Find first free bit in bitmap, mark as used
3. **Deallocation**: Clear bit in bitmap to mark as free

The allocator uses a bitmap to track frame allocation status efficiently.

### Virtual Memory

Virtual memory uses SV39 (3-level page tables) with 4KB pages.

#### Page Table Structure

```
Virtual Address (39 bits):
[38:30] VPN[2] | [29:21] VPN[1] | [20:12] VPN[0] | [11:0] Offset

Page Table Entry (64 bits):
[63:54] Reserved | [53:28] PPN[2] | [27:19] PPN[1] | [18:10] PPN[0] | [9:0] Flags
```

#### Address Space Layout

```
User Space (Per Process):
  0x0000000000000000 - 0x0000003FFFFFFFFF (256GB)
  0x0000000000001000 - Program text
  0x0000000000002000 - Program data  
  0x0000003FFFFFF000 - User stack (grows down)

Kernel Space (Shared):
  0xFFFFFFFF80000000 - 0xFFFFFFFFFFFFFFFF
  0xFFFFFFFF80000000 - Kernel text/data (identity mapped)
  0xFFFFFFFF88000000 - Kernel heap start
  0xFFFFFFFF8A000000 - Kernel heap end
```

### Kernel Heap

The kernel uses a bump allocator without deallocation support.

```zig
// kernel/memory/kalloc.zig
const HEAP_SIZE = 512 * 1024; // 512KB
var heap_memory: [HEAP_SIZE]u8 align(16) = undefined;
var heap_offset: usize = 0;
```

Design rationale: Simplicity over efficiency. No runtime allocations after boot.

## Process Management

### Process Structure

```zig
// kernel/process/core.zig
pub const Process = struct {
    pid: PID,
    state: ProcessState,
    context: Context,
    user_frame: ?*trap.TrapFrame,
    stack: []u8,
    name: [16]u8,
    parent: ?*Process,
    exit_code: i32,
    is_kernel: bool,
    cwd: [256]u8,
    cwd_len: usize,
    
    // Simple linked list for process queue
    next: ?*Process,
};

pub const ProcessState = enum {
    UNUSED,
    EMBRYO,
    SLEEPING,
    RUNNABLE,
    RUNNING,
    ZOMBIE,
};
```

### Process Table

Static allocation of 64 process slots:

```zig
var process_table: [MAX_PROCESSES]Process = undefined;
var next_pid: u32 = 1;
```

### Scheduling Algorithm

Simple round-robin scheduler:

1. Find next RUNNABLE process
2. Switch page tables
3. Restore context
4. Return to user mode

```zig
// kernel/process/scheduler.zig
pub fn schedule() void {
    const old = current_process;
    
    // Find next runnable process
    var next_idx = (current_process_idx + 1) % MAX_PROCESSES;
    while (next_idx != current_process_idx) {
        if (process_table[next_idx].state == .RUNNABLE) break;
        next_idx = (next_idx + 1) % MAX_PROCESSES;
    }
    
    // Switch to new process
    current_process_idx = next_idx;
    current_process = &process_table[next_idx];
    context_switch(&old.context, &current_process.context);
}
```

### Context Switching

Assembly implementation (`kernel/arch/riscv/context.S`) saves/restores:
- All general purpose registers (x1-x31)
- Supervisor registers (satp, sepc, sstatus)
- Stack pointer and return address

The context switch is performed by `context_switch(old, new)` which:
1. Saves current context to old->context
2. Loads new context from new->context
3. Returns in the new process context

## Virtual File System

### VFS Architecture

```
     Applications
          |
    +-----v-----+
    |    VFS    |  <- Generic interface
    +-----------+
    |  SimpleFS |  <- Filesystem implementation
    +-----------+
    |  RamDisk  |  <- Block device
    +-----------+
```

### VNode Structure

```zig
// kernel/fs/vfs.zig
pub const VNode = struct {
    name: [256]u8 = undefined,
    name_len: usize = 0,
    node_type: NodeType,
    size: usize = 0,
    parent: ?*VNode = null,
    
    // For directories
    children: ?*VNode = null,
    next_sibling: ?*VNode = null,
    
    // For files - simple fixed-size buffer
    data: [1024]u8 = undefined,
    data_size: usize = 0,
    
    // Reference counting
    ref_count: usize = 0,
};

pub const NodeType = enum(u8) {
    FILE = 1,
    DIRECTORY = 2,
    DEVICE = 3,
};
```

### File Descriptor Table

Each process has 16 file descriptors managed in the file module:

```zig
// kernel/file/types.zig  
pub const FileTable = struct {
    files: [MAX_FILES]?OpenFile,
};

pub const OpenFile = struct {
    vnode: *vfs.VNode,
    offset: usize,
    readable: bool,
    writable: bool,
};
```

### SimpleFS

A minimal filesystem with:
- Fixed 128KB RAM disk
- 512-byte blocks
- Simple directory structure
- No permissions or timestamps

## System Call Interface

### System Call Mechanism

1. **User Request**: `ecall` instruction
2. **Trap Entry**: Save context, enter kernel
3. **Dispatch**: Route to handler based on syscall number
4. **Execution**: Perform requested operation
5. **Return**: Restore context, return to user

### System Call Numbers

```zig
// abi/sysno.zig
pub const sys_read = 63;
pub const sys_write = 64;
pub const sys_open = 1024;
pub const sys_close = 57;
pub const sys_fork = 220;
pub const sys_execve = 221;
pub const sys_exit = 93;
pub const sys_wait = 260;
pub const sys_getpid = 172;
pub const sys_chdir = 49;
pub const sys_time = 1062;
// ... more syscalls
```

### System Call Implementation Example

```zig
// kernel/syscalls/fs.zig
pub fn sys_write(fd: usize, ubuf: usize, len: usize) isize {
    const getFile = file_getFile orelse return defs.ENOSYS;
    const writeFile = file_write orelse return defs.ENOSYS;
    
    const f = getFile(@as(i32, @intCast(fd))) orelse return defs.EBADF;
    var tmp: [256]u8 = undefined;
    var left = len;
    var off: usize = 0;
    
    while (left > 0) {
        const n = if (left > tmp.len) tmp.len else left;
        // Copy from user space
        copy.copyin(&tmp, ubuf + off, n) catch return defs.EFAULT;
        // Write to file
        const written = writeFile(f, &tmp, n);
        if (written < 0) return written;
        left -= @intCast(written);
        off += @intCast(written);
    }
    return @intCast(off);
}
```

## Interrupt and Trap Handling

### Trap Types

1. **Exceptions**: Synchronous events (page faults, illegal instructions)
2. **System Calls**: User-requested kernel services
3. **Interrupts**: Asynchronous hardware events

### Trap Entry Flow

```
trap_entry (kernel/arch/riscv/trap.S):
  1. Save all 32 general-purpose registers
  2. Save CSRs (sepc, sstatus, scause, stval)
  3. Load kernel stack pointer from sscratch
  4. Call trap_handler(trap_frame)
  5. Restore all registers from trap frame
  6. sret to return to interrupted context
```

### Interrupt Sources

- **Timer**: CLINT timer interrupts for scheduling
- **UART**: Serial port input/output
- **External**: Via PLIC (Platform Level Interrupt Controller)

### PLIC Configuration

```zig
// kernel/driver/plic.zig
pub fn init() void {
    // Enable UART interrupt
    enableInterrupt(IRQ.UART0, priority = 1);
    
    // Set threshold to 0 (accept all priorities)
    setThreshold(hart = 0, context = 1, threshold = 0);
}
```

## Device Drivers

### UART Driver

Simple UART driver for QEMU:

```zig
// kernel/driver/uart/core.zig
pub const Uart = struct {
    addr: *volatile u8,

    pub fn init(base_addr: usize) Uart {
        return Uart{ .addr = @as(*volatile u8, @ptrFromInt(base_addr)) };
    }

    pub fn putc(self: *const Uart, c: u8) void {
        self.addr.* = c;
    }

    pub fn getc(self: *const Uart) ?u8 {
        const lsr_addr = @as(*volatile u8, @ptrFromInt(@intFromPtr(self.addr) + 5));
        if ((lsr_addr.* & 1) != 0) {
            return self.addr.*;
        }
        return null;
    }
};
```

### RAM Disk Driver

Simple memory-backed block device:

```zig
// kernel/driver/ramdisk.zig
pub const RamDisk = struct {
    data: []u8,
    size: usize,
    block_size: usize = 512,
    
    pub fn readBlock(self: *RamDisk, block_num: usize, buffer: []u8) !void {
        const offset = block_num * self.block_size;
        if (offset + buffer.len > self.size) return error.InvalidBlock;
        @memcpy(buffer, self.data[offset..][0..buffer.len]);
    }
};
```

## User-Kernel Boundary

### Protection Mechanisms

1. **Privilege Levels**: User mode (U) vs Supervisor mode (S)
2. **Page Protection**: User pages not accessible in kernel mode
3. **Syscall Validation**: All user pointers validated before access

### User Memory Access

```zig
// kernel/user/copy.zig
pub fn copyout(dest: usize, src: []const u8) !void {
    // Validate destination address
    if (!isUserAddress(dest)) return error.InvalidAddress;
    
    // Find page and check permissions
    const pte = walkPageTable(dest) orelse return error.UnmappedAddress;
    if (!pte.isValid() or !pte.isUser() or !pte.isWriteable()) {
        return error.PermissionDenied;
    }
    
    // Perform copy
    const user_ptr = @as([*]u8, @ptrFromInt(dest));
    @memcpy(user_ptr, src);
}
```

### Security Boundaries

- Kernel memory never mapped in user space
- User cannot execute privileged instructions
- All system resources accessed via syscalls
- No direct hardware access from user mode

## Security Model

### Current Security Features

1. **Memory Isolation**: Process address spaces are separate
2. **Privilege Separation**: Clear kernel/user boundary  
3. **Input Validation**: All syscall parameters validated
4. **Static Allocation**: Predictable memory usage

### Security Limitations

1. **No User Permissions**: All processes run as single user
2. **No File Permissions**: All files accessible to all
3. **No Resource Limits**: Processes can exhaust resources
4. **Limited Randomization**: Fixed memory layout

### Future Security Enhancements

1. Implement user/group permissions
2. Add resource quotas
3. Implement ASLR
4. Add capability-based security

## Performance Characteristics

### Memory Usage

- Kernel: ~1MB code + data
- Kernel heap: 512KB
- Per process: 4KB kernel stack + page tables
- Static limits: 64 processes, 100 VFS nodes

### Scheduling Overhead

- Context switch: ~100 cycles
- System call: ~50 cycles  
- Interrupt handling: ~200 cycles

### Scalability Limits

- Maximum 64 concurrent processes
- Maximum 100 filesystem nodes
- Maximum 8 child processes per parent
- Fixed 128KB RAM disk

## Code Organization

### Directory Structure

```
claudia/
├── kernel/
│   ├── arch/riscv/    # Architecture-specific code
│   ├── driver/        # Device drivers
│   ├── file/          # File operations
│   ├── fs/            # Filesystem implementation
│   ├── memory/        # Memory management
│   ├── process/       # Process management
│   ├── syscalls/      # System call handlers
│   ├── trap/          # Interrupt/exception handling
│   └── user/          # User memory operations
├── userland/
│   ├── bin/           # User programs
│   ├── sbin/          # System programs
│   ├── shell/         # Shell implementation
│   └── syscalls/      # Syscall wrappers
├── abi/               # Kernel-user interface
└── docs/              # Documentation
```

### Build System

- Zig build system
- Separate kernel and userland compilation
- Embedded userland binaries in kernel
- Single bootable image output

## Testing Strategy

### Unit Testing

- Memory allocator edge cases
- Page table operations
- VFS operations

### Integration Testing

- Process lifecycle
- System call sequences
- Interrupt handling

### Stress Testing

- Process creation loops
- Memory exhaustion
- Concurrent file operations

## Future Directions

### Short Term

1. Implement memory deallocation
2. Add VFS node recycling  
3. Fix TTY race conditions
4. Improve error handling

### Medium Term

1. Multi-core support
2. Network stack
3. Persistent storage
4. Dynamic linking

### Long Term

1. Security enhancements
2. POSIX compliance
3. Device driver framework
4. Container support