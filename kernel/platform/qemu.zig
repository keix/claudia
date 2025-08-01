// QEMU virt machine platform definitions
// Platform-specific memory layout and device addresses

// Memory layout for QEMU virt machine
pub const MemoryLayout = struct {
    // UART
    pub const UART0_BASE: u64 = 0x10000000;
    pub const UART0_IRQ: u32 = 10;

    // Test device for shutdown/reboot
    pub const TEST_DEVICE_BASE: u64 = 0x100000;
    pub const TEST_SHUTDOWN_VALUE: u32 = 0x5555;
    pub const TEST_REBOOT_VALUE: u32 = 0x7777;

    // CLINT (Core Local Interruptor)
    pub const CLINT_BASE: u64 = 0x02000000;
    pub const CLINT_MTIMECMP: u64 = CLINT_BASE + 0x4000;
    pub const CLINT_MTIME: u64 = CLINT_BASE + 0xbff8;

    // PLIC (Platform-Level Interrupt Controller)
    pub const PLIC_BASE: u64 = 0x0c000000;
    pub const PLIC_PRIORITY: u64 = PLIC_BASE + 0x0;
    pub const PLIC_PENDING: u64 = PLIC_BASE + 0x1000;
    pub const PLIC_ENABLE: u64 = PLIC_BASE + 0x2000;
    pub const PLIC_THRESHOLD: u64 = PLIC_BASE + 0x200000;
    pub const PLIC_CLAIM: u64 = PLIC_BASE + 0x200004;
};

// Platform-specific initialization
pub fn init() void {
    // QEMU virt machine doesn't need special platform initialization
    // Hardware is already set up by QEMU
}

// Platform-specific shutdown
pub fn shutdown() noreturn {
    const test_device = @as(*volatile u32, @ptrFromInt(MemoryLayout.TEST_DEVICE_BASE));
    test_device.* = MemoryLayout.TEST_SHUTDOWN_VALUE;

    // If shutdown didn't work, hang
    while (true) {
        asm volatile ("wfi");
    }
}

// Platform-specific reboot
pub fn reboot() noreturn {
    const test_device = @as(*volatile u32, @ptrFromInt(MemoryLayout.TEST_DEVICE_BASE));
    test_device.* = MemoryLayout.TEST_REBOOT_VALUE;

    // If reboot didn't work, hang
    while (true) {
        asm volatile ("wfi");
    }
}
