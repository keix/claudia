// Common memory management types and constants

pub const PAGE_SIZE: usize = 4096;
pub const PAGE_SHIFT: u6 = 12;

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