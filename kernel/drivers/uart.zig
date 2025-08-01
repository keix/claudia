// Minimal UART driver for RISC-V platforms
// Simple character output only

const std = @import("std");
const platform = @import("../platform/qemu.zig");

// UART instance
const Uart = struct {
    addr: *volatile u8,

    // Write a single character
    pub fn putc(self: *const Uart, c: u8) void {
        self.addr.* = c;
    }

    // Write a string
    pub fn puts(self: *const Uart, s: []const u8) void {
        for (s) |c| {
            self.putc(c);
        }
    }

    // Write a hex number
    pub fn putHex(self: *const Uart, value: u64) void {
        const hex_chars = "0123456789abcdef";
        self.puts("0x");

        var i: u6 = 60;
        while (true) : (i -= 4) {
            const nibble = @as(u8, @truncate((value >> i) & 0xf));
            self.putc(hex_chars[nibble]);
            if (i == 0) break;
        }
    }
};

// Global UART instance
var uart: Uart = undefined;
var initialized: bool = false;

// Initialize UART driver
pub fn init() void {
    uart = Uart{
        .addr = @as(*volatile u8, @ptrFromInt(platform.MemoryLayout.UART0_BASE)),
    };
    initialized = true;
}

// Write a character
pub fn putc(c: u8) void {
    if (!initialized) return;
    uart.putc(c);
}

// Write a string
pub fn puts(s: []const u8) void {
    if (!initialized) return;
    uart.puts(s);
}

// Write a hex number
pub fn putHex(value: u64) void {
    if (!initialized) return;
    uart.putHex(value);
}

// Debug print - add prefix for easy identification
pub fn debug(s: []const u8) void {
    puts("[DEBUG] ");
    puts(s);
}
