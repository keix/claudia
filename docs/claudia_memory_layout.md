# Claudia Memory Layout

This document describes the memory layout of Claudia OS on RISC-V 64-bit architecture.

## Overview

Claudia uses a traditional split between user space (lower half) and kernel space (upper half) of the 64-bit virtual address space:

- **User Space**: `0x0000_0000_0000_0000` - `0x7FFF_FFFF_FFFF_FFFF` (lower 128 TiB)
- **Kernel Space**: `0x8000_0000_0000_0000` - `0xFFFF_FFFF_FFFF_FFFF` (upper 128 TiB)

## Physical Memory Map (QEMU virt machine)

```
0x0000_0000 - 0x0000_0FFF : Reserved
0x0000_1000 - 0x01FF_FFFF : Various MMIO devices
0x0200_0000 - 0x0200_FFFF : CLINT (Core Local Interruptor) - 64KB
0x0C00_0000 - 0x0FFF_FFFF : PLIC (Platform Level Interrupt Controller) - 64MB
0x1000_0000 - 0x1000_0FFF : UART0 (NS16550) - 4KB
0x1000_1000 - 0x7FFF_FFFF : Reserved for future devices
0x8000_0000 - 0x87FF_FFFF : RAM (128MB default in QEMU)
0x8800_0000 - ...         : Extended RAM (if configured)
```

## Kernel Virtual Memory Layout

```
0x8000_0000 - 0x801F_FFFF : OpenSBI firmware (2MB)
0x8020_0000 - 0x803F_FFFF : Kernel code (.text) and read-only data (.rodata)
0x8040_0000 - 0x8043_FFFF : Kernel heap (256KB)
0x8044_0000 - 0x807F_FFFF : Kernel data (.data, .bss) and stacks
0x8080_0000 - 0x87EF_FFFF : Free memory for frame allocation
0x87F0_0000 - 0x87F0_3FFF : Kernel stack (16KB per CPU)
0x87F0_4000 - 0x87FF_FFFF : Reserved
0x8800_0000 - ...         : Extended memory (if available)
```

### Detailed Kernel Memory Regions

#### OpenSBI Region (0x8000_0000 - 0x801F_FFFF)
- Runtime firmware services
- M-mode trap handlers
- SBI call implementations

#### Kernel Code (0x8020_0000 - 0x803F_FFFF)
- `.text`: Kernel executable code
- `.rodata`: Read-only data (strings, constants)
- Identity mapped (VA = PA)

#### Kernel Heap (0x8040_0000 - 0x8043_FFFF)
- Dynamic memory allocation for kernel
- 256KB total size
- Used for:
  - Page tables
  - Process structures
  - VFS nodes
  - Dynamic buffers

#### Kernel Stack (0x87F0_0000 - 0x87F0_3FFF)
- Per-CPU kernel stacks
- 16KB per stack (4 pages)
- Grows downward
- Guard page at bottom to detect overflow

## User Virtual Memory Layout

```
0x0000_0000 - 0x00FF_FFFF : Reserved (null pointer protection)
0x0100_0000 - 0x01FF_FFFF : ELF program load area (16MB)
0x0200_0000 - 0x3FFF_FFFF : Reserved for dynamic libraries
0x4000_0000 - 0x4FFF_FFFF : User code region (256MB)
0x5000_0000 - 0x5FFF_FFFF : User stack region (256MB)
0x6000_0000 - 0x6FFF_FFFF : User heap region (256MB)
0x7000_0000 - 0x7FFF_FFFF : Reserved for shared memory
```

### User Process Memory Regions

#### Code Region (0x4000_0000 - 0x4FFF_FFFF)
- Executable code and read-only data
- Permissions: R-X (read, execute)
- Shared between parent and child after fork

#### Stack Region (0x5000_0000 - 0x5FFF_FFFF)
- User stack (grows downward)
- Initial size: 64KB (16 pages)
- Permissions: RW- (read, write)
- Per-process, copied on fork

#### Heap Region (0x6000_0000 - 0x6FFF_FFFF)
- Dynamic memory (brk/sbrk)
- Initial size: 0, grows on demand
- Permissions: RW- (read, write)
- Per-process, copied on fork

## Page Table Structure (Sv39)

Claudia uses RISC-V Sv39 virtual memory system:
- 39-bit virtual addresses
- 3-level page table hierarchy
- 4KB pages (12-bit offset)
- 9 bits per level (512 entries)

### Virtual Address Format
```
 38    30 29    21 20    12 11         0
+--------+--------+--------+------------+
| VPN[2] | VPN[1] | VPN[0] | Page Offset|
+--------+--------+--------+------------+
    9        9        9          12
```

### Page Table Entry (PTE) Format
```
 63    54 53                  10 9   8 7 6 5 4 3 2 1 0
+--------+----------------------+-----+-+-+-+-+-+-+-+-+
|Reserved|       PPN[2:0]       | RSW |D|A|G|U|X|W|R|V|
+--------+----------------------+-----+-+-+-+-+-+-+-+-+
```

- V: Valid
- R: Readable
- W: Writable
- X: Executable
- U: User accessible
- G: Global mapping
- A: Accessed
- D: Dirty
- RSW: Reserved for software
- PPN: Physical page number

## Memory Allocation

### Physical Memory Management
- **Frame Allocator**: Bitmap-based allocator
- **Frame Size**: 4KB (PAGE_SIZE)
- **Allocation**: First-fit algorithm
- **Reserved Frames**: OpenSBI and kernel regions

### Virtual Memory Management
- **Kernel Allocator**: Simple bump allocator for kernel heap
- **User Memory**: Demand paging (if implemented)
- **Copy-on-Write**: Fork optimization (if implemented)

## MMIO Device Mappings

All MMIO devices are identity mapped in kernel space:

| Device | Virtual Address | Physical Address | Size |
|--------|----------------|------------------|------|
| UART0  | 0x1000_0000 | 0x1000_0000 | 4KB |
| CLINT  | 0x0200_0000 | 0x0200_0000 | 64KB |
| PLIC   | 0x0C00_0000 | 0x0C00_0000 | 6MB |

## Special Mappings

### Kernel Global Mappings
These mappings exist in all process page tables:
1. Kernel code/data (identity mapped)
2. MMIO devices (identity mapped)
3. Kernel heap
4. Kernel stack (per-CPU)

### Process-Specific Mappings
Each process has its own:
1. User code/data/heap/stack regions
2. Per-process kernel stack (child processes)

## Memory Constants (from kernel/memory/types.zig)

```zig
// Page parameters
PAGE_SIZE     = 4096    // 4KB pages
PAGE_SHIFT    = 12      // log2(PAGE_SIZE)
PAGE_MASK     = 4095    // PAGE_SIZE - 1

// Kernel memory
KERNEL_BASE       = 0x8000_0000
KERNEL_HEAP_BASE  = 0x8040_0000
KERNEL_HEAP_SIZE  = 256KB
KERNEL_STACK_BASE = 0x87F0_0000
KERNEL_STACK_SIZE = 16KB

// User memory
USER_CODE_BASE  = 0x4000_0000
USER_CODE_SIZE  = 64KB
USER_STACK_BASE = 0x5000_0000
USER_STACK_SIZE = 64KB
USER_HEAP_BASE  = 0x6000_0000
USER_HEAP_SIZE  = 64KB
```

## Security Considerations

1. **W^X Policy**: Memory regions are either writable or executable, never both
2. **User/Kernel Separation**: User processes cannot access kernel memory
3. **Null Pointer Protection**: First 16MB of address space is unmapped
4. **Stack Guard Pages**: Unmapped pages below stacks to detect overflow
5. **ASLR**: Not implemented (educational simplicity)

## Future Enhancements

1. **Demand Paging**: Load pages only when accessed
2. **Copy-on-Write**: Optimize fork() by sharing pages
3. **Swap Support**: Page out to disk when memory is full
4. **Large Pages**: 2MB/1GB pages for better TLB usage
5. **NUMA Support**: Non-uniform memory access optimization