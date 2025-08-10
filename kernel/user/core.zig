// User program management for Claudia kernel
// This will contain the real implementation for user program loading and execution

const std = @import("std");
const uart = @import("../driver/uart/core.zig");
const memory = @import("memory.zig");
const csr = @import("../arch/riscv/csr.zig");

// Import test module
const test_loader = @import("test/loader.zig");

// Import user mode switch function
extern fn switch_to_user_mode(entry_point: u64, user_stack: u64, kernel_stack: u64) void;

// Global user memory context for testing
var test_user_context: memory.UserMemoryContext = undefined;

// Initialize user subsystem
pub fn init() void {
    memory.init();
    test_user_context = memory.UserMemoryContext.init();
    uart.puts("[user] User subsystem initialized\n");
}

// Execute user program with proper memory management
pub fn executeUserProgram(code: []const u8, args: []const u8) !void {
    _ = args;
    uart.puts("[user] Setting up user address space\n");

    // Setup user address space
    test_user_context.setupAddressSpace() catch |err| {
        uart.puts("[user] Failed to setup address space: ");
        switch (err) {
            error.OutOfMemory => uart.puts("OutOfMemory"),
            else => uart.puts("Unknown error"),
        }
        uart.puts("\n");
        return;
    };

    uart.puts("[user] User address space created successfully\n");

    // Copy program to user code region
    if (!memory.copyToRegion(&test_user_context.code_region, 0, code)) {
        uart.puts("[user] Failed to copy program to user memory\n");
        return;
    }

    uart.puts("[user] Copied ");
    uart.putHex(code.len);
    uart.puts(" bytes to code region\n");

    // Get user page table PPN for SATP
    const user_ppn = test_user_context.getPageTablePPN() orelse {
        uart.puts("[user] Failed to get user page table PPN\n");
        return;
    };

    // Set up user stack address
    const user_stack = memory.USER_STACK_BASE + memory.USER_STACK_SIZE - 16;

    // Set up kernel stack for trap handling
    var kernel_stack: [4096]u8 = undefined;
    const kernel_sp = @intFromPtr(&kernel_stack) + kernel_stack.len - 8;

    uart.puts("[user] Switching to user address space\n");
    uart.puts("[user] User PPN: ");
    uart.putHex(user_ppn);
    uart.puts("\n");

    // Switch to user page table
    const satp_value = csr.SATP_SV39 | user_ppn;
    csr.writeSatp(satp_value);
    csr.sfence_vma();

    uart.puts("[user] Switching to U-mode...\n");
    uart.puts("[user] Entry: ");
    uart.putHex(memory.USER_CODE_BASE);
    uart.puts(" User stack: ");
    uart.putHex(user_stack);
    uart.puts("\n");

    // Switch to user mode
    switch_to_user_mode(memory.USER_CODE_BASE, user_stack, kernel_sp);

    // Should never reach here
    uart.puts("[user] ERROR: Unexpectedly returned from user mode\n");
}

// Test function - will be removed when real implementation is ready
pub fn runTests() void {
    test_loader.testUserEcho();

    // Test the new user memory system
    uart.puts("[user] Testing new user memory system\n");
    testActualUserMode();
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
        executeUserProgram(code, "") catch |err| {
            uart.puts("[user] Execute user program failed: ");
            switch (err) {
                else => uart.puts("Unknown error"),
            }
            uart.puts("\n");
        };
    } else {
        uart.puts("[user] Invalid user program size: ");
        uart.putHex(code_size);
        uart.puts("\n");
    }
}
