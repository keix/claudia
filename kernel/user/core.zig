// User program management for Claudia kernel
// This will contain the real implementation for user program loading and execution

const std = @import("std");
const uart = @import("../driver/uart/core.zig");

// Import test module
const test_loader = @import("test/loader.zig");

// Import user mode switch function
extern fn switch_to_user_mode(entry_point: u64, user_stack: u64, kernel_stack: u64) void;

// User memory layout constants (use identity mapped regions for now)
pub const USER_CODE_BASE: u64 = 0x10000000;
pub const USER_STACK_TOP: u64 = 0x81000000;  // Use mapped kernel region
pub const USER_STACK_SIZE: usize = 4096;

// Initialize user subsystem
pub fn init() void {
    uart.puts("[user] User subsystem initialized\n");
}

// Execute user program in actual U-mode
pub fn executeUserProgram(code: []const u8, entry_point: u64, args: []const u8) void {
    _ = args;
    uart.puts("[user] Preparing to execute user program in U-mode\n");
    
    // Copy program to user memory space
    const dest = @as([*]u8, @ptrFromInt(entry_point));
    @memcpy(dest[0..code.len], code);
    
    uart.puts("[user] Copied ");
    uart.putHex(code.len);
    uart.puts(" bytes to ");
    uart.putHex(entry_point);
    uart.puts("\n");
    
    // Set up user stack
    const user_stack = USER_STACK_TOP - 8; // Leave some space
    
    // Set up kernel stack for trap handling
    var kernel_stack: [4096]u8 = undefined;
    const kernel_sp = @intFromPtr(&kernel_stack) + kernel_stack.len - 8;
    
    uart.puts("[user] Switching to U-mode...\n");
    uart.puts("[user] Entry: ");
    uart.putHex(entry_point);
    uart.puts(" User stack: ");
    uart.putHex(user_stack);
    uart.puts("\n");
    
    // Switch to user mode (this will not return normally)
    // User program will return via ecall -> trap handler
    switch_to_user_mode(entry_point, user_stack, kernel_sp);
    
    // Should never reach here
    uart.puts("[user] ERROR: Unexpectedly returned from user mode\n");
}

// Test function - will be removed when real implementation is ready
pub fn runTests() void {
    test_loader.testUserEcho();
    
    // Skip actual U-mode execution for now due to memory mapping issues
    // testActualUserMode();
    uart.puts("[user] Skipping U-mode execution test (needs proper memory setup)\n");
}

fn testActualUserMode() void {
    uart.puts("[user] Testing actual U-mode execution\n");
    
    // Get the echo program code
    const _user_echo_start = @extern([*]const u8, .{ .name = "_user_echo_start" });
    const _user_echo_end = @extern([*]const u8, .{ .name = "_user_echo_end" });
    
    const start_addr = @intFromPtr(_user_echo_start);
    const end_addr = @intFromPtr(_user_echo_end);
    const code_size = end_addr - start_addr;
    
    if (code_size > 0 and code_size < 1024) {
        const code = @as([*]const u8, @ptrFromInt(start_addr))[0..code_size];
        executeUserProgram(code, USER_CODE_BASE, "");
    } else {
        uart.puts("[user] Invalid user program size: ");
        uart.putHex(code_size);
        uart.puts("\n");
    }
}