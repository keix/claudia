// RISC-V Platform Level Interrupt Controller (PLIC)
// Manages external interrupts for RISC-V systems

const std = @import("std");
const config = @import("../config.zig");

// PLIC memory-mapped addresses for QEMU virt machine
const PLIC_BASE: u64 = 0x0c000000;
const PLIC_PRIORITY = PLIC_BASE + 0x000000; // Interrupt source priority
const PLIC_PENDING = PLIC_BASE + 0x001000; // Interrupt pending bits
const PLIC_ENABLE = PLIC_BASE + 0x002000; // Interrupt enable bits
const PLIC_THRESHOLD = PLIC_BASE + 0x200000; // Priority threshold
const PLIC_CLAIM = PLIC_BASE + 0x200000; // Claim/complete registers

// QEMU virt machine interrupt assignments
pub const IRQ = struct {
    pub const VIRTIO_BASE: u32 = 1; // VirtIO devices start at IRQ 1
    pub const UART0: u32 = 10; // UART0 serial port
    pub const PCIE_BASE: u32 = 32; // PCIe devices start at IRQ 32
};

// Initialize PLIC for specific interrupts
pub fn init() void {
    // Enable UART interrupt
    enableInterrupt(IRQ.UART0, 1);

    // Set threshold to 0 to accept all priorities
    setThreshold(0, 1, 0);
}

// Enable an interrupt source with given priority
pub fn enableInterrupt(irq: u32, priority: u8) void {
    // Set interrupt priority (non-zero enables it)
    const priority_addr = @as(*volatile u32, @ptrFromInt(PLIC_PRIORITY + irq * 4));
    priority_addr.* = priority;

    // Enable interrupt for hart 0, context 1 (supervisor mode)
    const enable_offset = config.Interrupt.PLIC_HART0_S_MODE_OFFSET;
    const enable_addr = @as(*volatile u32, @ptrFromInt(PLIC_ENABLE + enable_offset));
    enable_addr.* |= @as(u32, 1) << @intCast(irq);
}

// Set priority threshold for a hart/context
pub fn setThreshold(hart: u32, context: u32, threshold: u32) void {
    // Calculate offset: each hart has 2 contexts (M-mode=0, S-mode=1)
    const offset = (hart * 2 + context) * config.Interrupt.PLIC_CONTEXT_STRIDE;
    const threshold_addr = @as(*volatile u32, @ptrFromInt(PLIC_THRESHOLD + offset));
    threshold_addr.* = threshold;
}

// Claim an interrupt (returns IRQ number)
pub fn claim(hart: u32, context: u32) u32 {
    const offset = (hart * 2 + context) * config.Interrupt.PLIC_CONTEXT_STRIDE + 4; // +4 for claim register
    const claim_addr = @as(*volatile u32, @ptrFromInt(PLIC_CLAIM + offset));
    return claim_addr.*;
}

// Complete interrupt handling
pub fn complete(hart: u32, context: u32, irq: u32) void {
    const offset = (hart * 2 + context) * config.Interrupt.PLIC_CONTEXT_STRIDE + 4; // +4 for complete register
    const complete_addr = @as(*volatile u32, @ptrFromInt(PLIC_CLAIM + offset));
    complete_addr.* = irq;
}
