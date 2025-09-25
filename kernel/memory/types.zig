/// Common memory management types and constants
///
/// This module defines the core types and memory layout constants used throughout
/// the Claudia kernel. All memory addresses and sizes are defined here to ensure
/// consistency across the codebase.
///
/// Memory layout:
/// - User space: 0x00000000 - 0x7FFFFFFF (2GB)
/// - Kernel space: 0x80000000 - 0xFFFFFFFF (2GB)
/// - MMIO devices are mapped in low addresses (UART, CLINT, PLIC)

pub const PAGE_SIZE: usize = 4096;
pub const PAGE_SHIFT: u6 = 12;
pub const PAGE_MASK: usize = PAGE_SIZE - 1;

/// Align an address up to the next page boundary
pub inline fn alignPageUp(addr: usize) usize {
    return (addr + PAGE_MASK) & ~PAGE_MASK;
}

/// Align an address down to the previous page boundary
pub inline fn alignPageDown(addr: usize) usize {
    return addr & ~PAGE_MASK;
}

/// Check if an address is page-aligned
pub inline fn isPageAligned(addr: usize) bool {
    return (addr & PAGE_MASK) == 0;
}

// Physical memory information
pub const PhysicalMemory = struct {
    base: usize,
    size: usize,
    available: usize,
};

// Page table entry flags for RISC-V Sv39
pub const PTE_V: u64 = 1 << 0; // Valid
pub const PTE_R: u64 = 1 << 1; // Read
pub const PTE_W: u64 = 1 << 2; // Write
pub const PTE_X: u64 = 1 << 3; // Execute
pub const PTE_U: u64 = 1 << 4; // User
pub const PTE_G: u64 = 1 << 5; // Global
pub const PTE_A: u64 = 1 << 6; // Accessed
pub const PTE_D: u64 = 1 << 7; // Dirty

// Kernel memory layout constants
pub const KERNEL_BASE: u64 = 0x80000000; // Kernel code/data start
pub const KERNEL_HEAP_BASE: u64 = 0x80400000; // Kernel heap start (4MB into kernel)
pub const KERNEL_HEAP_SIZE: usize = 256 * 1024; // 256KB kernel heap
pub const KERNEL_END: u64 = 0x80800000; // Map up to 8MB for kernel (generous allocation)
pub const KERNEL_STACK_BASE: u64 = 0x87F00000; // Kernel stack near end of kernel region
pub const KERNEL_STACK_SIZE: usize = 4 * PAGE_SIZE; // 16KB kernel stack

// User memory layout constants
pub const USER_CODE_BASE: u64 = 0x40000000; // User code region
pub const USER_CODE_SIZE: usize = 16 * PAGE_SIZE; // 64KB user code
pub const USER_STACK_BASE: u64 = 0x50000000; // User stack region
pub const USER_STACK_SIZE: usize = 16 * PAGE_SIZE; // 64KB user stack
pub const USER_HEAP_BASE: u64 = 0x60000000; // User heap region
pub const USER_HEAP_SIZE: usize = 16 * PAGE_SIZE; // 64KB user heap

// MMIO addresses for RISC-V virt machine
pub const UART_BASE: u64 = 0x10000000; // UART0 base address
pub const CLINT_BASE: u64 = 0x02000000; // Core Local Interruptor
pub const CLINT_SIZE: usize = 0x10000; // 64KB CLINT region
pub const PLIC_BASE: u64 = 0x0c000000; // Platform Level Interrupt Controller
pub const PLIC_SIZE: usize = 0x600000; // 6MB PLIC region
