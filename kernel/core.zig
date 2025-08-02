const std = @import("std");
const csr = @import("arch/riscv/csr.zig");
const uart = @import("driver/uart.zig");
const proc = @import("process/proc.zig");

// Simple stack allocator for testing
var stack_memory: [4096 * 4]u8 = undefined;
var stack_offset: usize = 0;

fn allocStack(size: usize) []u8 {
    const aligned_size = (size + 7) & ~@as(usize, 7); // 8-byte align
    if (stack_offset + aligned_size > stack_memory.len) {
        return &[_]u8{}; // Out of memory
    }

    const stack = stack_memory[stack_offset .. stack_offset + aligned_size];
    stack_offset += aligned_size;
    return stack;
}

pub fn init() noreturn {
    uart.init();
    uart.puts("Hello Claudia!!\n");

    // Initialize process scheduler
    proc.Scheduler.init();

    // Test process creation
    testProcessSystem();

    // Hand over control to scheduler
    uart.puts("Handing control to scheduler\n");
    proc.Scheduler.run();
}

fn testProcessSystem() void {
    uart.puts("Testing process system...\n");

    // Allocate some test processes
    const stack1 = allocStack(1024);
    const stack2 = allocStack(1024);
    const stack3 = allocStack(1024);

    if (stack1.len == 0 or stack2.len == 0 or stack3.len == 0) {
        uart.puts("Failed to allocate stacks\n");
        return;
    }

    // Create test processes
    if (proc.Scheduler.allocProcess("init", stack1)) |p1| {
        proc.Scheduler.makeRunnable(p1);
    }

    if (proc.Scheduler.allocProcess("shell", stack2)) |p2| {
        proc.Scheduler.makeRunnable(p2);
    }

    if (proc.Scheduler.allocProcess("worker", stack3)) |p3| {
        proc.Scheduler.makeRunnable(p3);
    }

    // Test scheduling
    uart.puts("Running scheduler test...\n");
    for (0..5) |i| {
        uart.puts("Schedule iteration ");
        uart.putHex(i);
        uart.puts("\n");
        proc.Scheduler.schedule();
    }

    uart.puts("Process system test completed\n");
}
