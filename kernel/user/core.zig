// User program management for Claudia kernel
// This will contain the real implementation for user program loading and execution

const std = @import("std");
const uart = @import("../driver/uart/core.zig");
const memory = @import("memory.zig");
const csr = @import("../arch/riscv/csr.zig");
const virtual = @import("../memory/virtual.zig");
const types = @import("../memory/types.zig");

// Import test module
const test_loader = @import("test/loader.zig");

// Import safe user mode switch function (includes SATP switching)
extern fn switch_to_user_mode(entry_point: u64, user_stack: u64, kernel_stack: u64, satp_val: u64) void;

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

    uart.puts("[user] Switching to user address space\n");
    uart.puts("[user] User PPN: ");
    uart.putHex(user_ppn);
    uart.puts("\n");

    // User page table is now complete with kernel global mappings and user regions
    uart.puts("[user] User page table ready, switching to U-mode\n");

    const asid: u16 = 0; // Use ASID 0 for simplicity first
    const satp_value = composeSatp(user_ppn, asid);

    // Set up user stack address
    const user_stack = memory.USER_STACK_BASE + memory.USER_STACK_SIZE - 16;

    // Get proper kernel stack from high common region
    const kernel_sp = memory.getKernelStackTop();

    uart.puts("[user] Entry: ");
    uart.putHex(memory.USER_CODE_BASE);
    uart.puts(" User stack: ");
    uart.putHex(user_stack);
    uart.puts(" Kernel stack: ");
    uart.putHex(kernel_sp);
    uart.puts(" SATP: ");
    uart.putHex(satp_value);
    uart.puts("\n");

    // Verify kernel stack is properly mapped in user PT
    if (!test_user_context.verifyMapping(kernel_sp)) {
        uart.puts("[user] ERROR: Kernel stack not mapped in user PT!\n");
        return;
    }
    uart.puts("[user] Kernel stack mapping verified\n");

    // CRITICAL: After this call, we switch page tables inside the trampoline
    // No more UART access until we return via trap or the program exits
    switch_to_user_mode(memory.USER_CODE_BASE, user_stack, kernel_sp, satp_value);

    // Should never reach here normally (user program exits via system call)
    uart.puts("[user] ERROR: Unexpectedly returned from user mode\n");
}

// Test function - will be removed when real implementation is ready
pub fn runTests() void {
    test_loader.testUserEcho();

    // Test the new user memory system
    uart.puts("[user] Testing new user memory system\n");
    testActualUserMode();
}

// Compose SATP value with proper SV39 mode and ASID
fn composeSatp(ppn: u64, asid: u16) u64 {
    const MODE_SV39: u64 = 8;
    return (MODE_SV39 << 60) | (@as(u64, asid) << 44) | ppn;
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
