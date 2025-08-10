// Test user program loader - temporary implementation for testing only
// This will be replaced with a proper user program loader later

const std = @import("std");
const csr = @import("../../arch/riscv/csr.zig");
const uart = @import("../../driver/uart/core.zig");
const trap = @import("../../trap/core.zig");

// Import the assembled user program
extern const _user_echo_start: u8;

// Test user mode execution with hardcoded echo program
pub fn testUserEcho() void {
    uart.puts("[test] Testing user mode echo program\n");

    // For now, just simulate the echo program by calling syscalls directly
    // This tests the syscall mechanism without actual user mode switching

    // Simulate write syscall
    var write_frame = std.mem.zeroes(trap.TrapFrame);
    write_frame.a7 = 64; // sys_write
    write_frame.a0 = 1; // stdout

    // Use the test message directly
    const test_msg = "Hello from user!\n";
    write_frame.a1 = @intFromPtr(test_msg.ptr);
    write_frame.a2 = test_msg.len;
    write_frame.cause = 8; // EcallFromUMode

    trap.trapHandler(&write_frame);

    if (write_frame.a0 == test_msg.len) {
        uart.puts("[test] Write syscall simulation successful\n");
    } else {
        uart.puts("[test] Write syscall simulation failed\n");
    }

    // Simulate exit syscall
    var exit_frame = std.mem.zeroes(trap.TrapFrame);
    exit_frame.a7 = 93; // sys_exit
    exit_frame.a0 = 0; // exit status
    exit_frame.cause = 8; // EcallFromUMode

    uart.puts("[test] Simulating exit syscall\n");
    // Note: We don't actually call this because it would terminate the kernel

    uart.puts("[test] User mode echo test completed\n");
}
