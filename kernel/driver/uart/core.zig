// Minimal UART driver for RISC-V platforms
// Simple character output only

const std = @import("std");
const platform = @import("../../platform/qemu.zig");

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

    // Read a single character (non-blocking)
    pub fn getc(self: *const Uart) ?u8 {
        // For QEMU's 16550 UART, check all relevant status
        const lsr_addr = @as(*volatile u8, @ptrFromInt(@intFromPtr(self.addr) + 5));
        const lsr = lsr_addr.*;

        // Check if data is ready (bit 0 of LSR)
        if ((lsr & 0x01) != 0) {
            const ch = self.addr.*;
            return ch; // Return any character, including 0
        }
        return null;
    }

    // Write a decimal number
    pub fn putDec(self: *const Uart, value: u64) void {
        if (value == 0) {
            self.putc('0');
            return;
        }

        var buf: [20]u8 = undefined;
        var i: usize = 0;
        var n = value;

        while (n > 0) : (i += 1) {
            buf[i] = @intCast('0' + (n % 10));
            n /= 10;
        }

        while (i > 0) {
            i -= 1;
            self.putc(buf[i]);
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

    // Initialize UART hardware for interrupt-driven input
    // Set up basic UART registers for 16550 compatibility
    const base_addr = platform.MemoryLayout.UART0_BASE;

    // Line Control Register (LCR) - offset 3
    const lcr_addr = @as(*volatile u8, @ptrFromInt(base_addr + 3));
    lcr_addr.* = 0x03; // 8 bits, no parity, 1 stop bit

    // FIFO Control Register (FCR) - offset 2
    const fcr_addr = @as(*volatile u8, @ptrFromInt(base_addr + 2));
    fcr_addr.* = 0x07; // Enable FIFO, clear RX/TX FIFOs

    // Interrupt Enable Register (IER) - offset 1
    const ier_addr = @as(*volatile u8, @ptrFromInt(base_addr + 1));
    ier_addr.* = 0x01; // Enable RX interrupt

    // Modem Control Register (MCR) - offset 4
    const mcr_addr = @as(*volatile u8, @ptrFromInt(base_addr + 4));
    mcr_addr.* = 0x03; // DTR, RTS active

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

// Read a character (non-blocking)
pub fn getc() ?u8 {
    if (!initialized) return null;
    return uart.getc();
}

// Write a decimal number
pub fn putDec(value: u64) void {
    if (!initialized) return;
    uart.putDec(value);
}
