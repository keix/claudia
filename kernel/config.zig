// Kernel configuration constants
// These are internal to the kernel and can be changed without affecting userland

const std = @import("std");

// Memory layout configuration
pub const MemoryLayout = struct {
    // Critical kernel addresses (QEMU virt specific)
    pub const KERNEL_INIT_START: u64 = 0x802bf000;
    pub const KERNEL_INIT_END: u64 = 0x802cf000;

    // Kernel stack sizes
    pub const BOOT_STACK_SIZE: usize = 4 * 4096; // 4 pages for boot
    pub const KERNEL_STACK_SIZE: usize = 8 * 4096; // 8 pages for kernel threads

    // Initrd scanning
    pub const INITRD_MAX_SCAN_SIZE: usize = 16 * 1024 * 1024; // 16MB

    // Device tree blob (DTB) handling
    pub const DTB_MAP_SIZE: usize = 1024 * 1024; // 1MB
    pub const DTB_CANDIDATE_1: u64 = 0x8fe00000;
    pub const DTB_CANDIDATE_2: u64 = 0x9fe00000;
    pub const DTB_MIN_ADDR: u64 = 0x80000000;
    pub const DTB_MAX_ADDR: u64 = 0xa0000000;
};

// Hardware timer configuration
pub const Timer = struct {
    // RISC-V timer frequency (platform specific)
    pub const FREQUENCY_HZ: u64 = 10_000_000; // 10MHz for QEMU
    pub const NANOSECONDS_PER_CYCLE: u64 = 100; // 1e9 / FREQUENCY_HZ

    // Boot time epoch (arbitrary starting point)
    pub const BOOT_EPOCH_SECONDS: i64 = 1700000000;
};

// Page table configuration
pub const PageTable = struct {
    // Entries per page table (architecture specific)
    pub const ENTRIES_PER_TABLE: usize = 512; // For Sv39

    // Maximum number of page tables to allocate
    pub const MAX_PAGE_TABLES: usize = 256;
};

// Interrupt configuration
pub const Interrupt = struct {
    // S-mode interrupt enable bits
    pub const SEIE_BIT: u64 = 1 << 9; // External interrupt enable
    pub const STIE_BIT: u64 = 1 << 5; // Timer interrupt enable

    // PLIC (Platform-Level Interrupt Controller) offsets
    pub const PLIC_HART0_S_MODE_OFFSET: u64 = 0x80;
    pub const PLIC_CONTEXT_STRIDE: u64 = 0x1000;
};

// File system configuration
pub const FileSystem = struct {
    // VFS limits
    pub const MAX_VNODES: usize = 128;
    pub const MAX_MOUNT_POINTS: usize = 16;

    // Buffer sizes
    pub const VFS_BUFFER_SIZE: usize = 2048;

    // File pool sizes
    pub const MAX_MEMFILES: usize = 32;
    pub const MAX_DIRFILES: usize = 16;
    pub const MAX_INODES: usize = 64;
    pub const INODE_DIRECT_BLOCKS: usize = 12;

    // SimpleFS configuration
    pub const SIMPLEFS_DATA_START_BLOCK: u32 = 9; // After superblock + bitmap
};

// Console/TTY configuration
pub const Console = struct {
    // Buffer sizes
    pub const RING_BUFFER_SIZE: usize = 256;
    pub const LINE_BUFFER_SIZE: usize = 256;

    // Magic number for TTY structure validation
    pub const TTY_MAGIC: u32 = 0xDEADBEEF;
};

// Debug configuration
pub const Debug = struct {
    // Enable verbose boot messages
    pub const VERBOSE_BOOT: bool = true;

    // Enable memory allocation tracking
    pub const TRACK_ALLOCATIONS: bool = false;
};
