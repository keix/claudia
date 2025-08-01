// Core kernel functionality

const std = @import("std");
const csr = @import("arch/riscv/csr.zig");

pub fn init() noreturn {
    // Initialize UART for output
    const uart = @as(*volatile u8, @ptrFromInt(csr.UART0));

    // Print welcome message
    const msg = "Hello from Claudia kernel core!\n";
    for (msg) |char| {
        uart.* = char;
    }

    // Now we boot in M-mode and transition to S-mode
    // Hart ID was read in M-mode, but we can try to read it via delegation
    print(uart, "Kernel running in S-mode (transitioned from M-mode)\n");

    // Enter idle loop with wfi
    print(uart, "Entering idle loop with wfi...\n");

    while (true) {
        csr.wfi();
    }
}

// Simple print function for strings
fn print(uart: *volatile u8, msg: []const u8) void {
    for (msg) |char| {
        uart.* = char;
    }
}

// Print a hex number
fn printHex(uart: *volatile u8, value: u64) void {
    const hex_chars = "0123456789abcdef";
    print(uart, "0x");

    // Print each nibble
    var i: u6 = 60;
    while (true) : (i -= 4) {
        const nibble = @as(u8, @truncate((value >> i) & 0xf));
        uart.* = hex_chars[nibble];
        if (i == 0) break;
    }
}
