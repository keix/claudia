const std = @import("std");
const csr = @import("arch/riscv/csr.zig");
const uart = @import("driver/uart/core.zig");
const proc = @import("process/core.zig");
const file = @import("file/core.zig");
const memory = @import("memory/core.zig");
const trap = @import("trap/core.zig");
const user = @import("user/core.zig");

// Simple stack allocator for init process
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

    // Initialize memory subsystem
    memory.init();

    // Initialize virtual memory
    memory.initVirtual() catch {
        while (true) {}
    };

    // Initialize kernel heap before enabling MMU
    const kalloc = @import("memory/kalloc.zig");
    kalloc.init() catch {
        while (true) {}
    };

    // Initialize file system
    file.FileTable.init();

    // Initialize trap handling
    trap.init();

    // Enable supervisor external interrupts for UART
    csr.enableInterrupts();

    // Enable external interrupts in SIE
    csr.csrs(csr.CSR.sie, 1 << 9); // SEIE bit

    // Initialize PLIC for UART interrupts
    initPLIC();

    // Enable MMU
    memory.enableMMU();

    // Initialize user subsystem
    user.init();

    // Initialize process scheduler
    proc.Scheduler.init();

    // Create and start initial user process (init)
    createInitProcess();

    // Start the process scheduler - this will handle all process scheduling
    proc.Scheduler.run();
}

fn createIdleProcess() void {
    // Allocate kernel stack for idle process
    const idle_stack = allocStack(4096);
    if (idle_stack.len == 0) {
        while (true) {
            csr.wfi();
        }
    }

    // Create the idle process using the regular process allocation
    if (proc.Scheduler.allocProcess("idle", idle_stack)) |idle_proc| {
        // Mark as kernel process so it won't try to go to user mode
        idle_proc.is_kernel = true;

        // Set the entry point to idleLoop
        idle_proc.context.ra = @intFromPtr(&idleLoop);

        // Make it runnable
        proc.Scheduler.makeRunnable(idle_proc);
    } else {
        while (true) {
            csr.wfi();
        }
    }
}

pub fn idleLoop() noreturn {
    // Simple idle loop - just yield frequently
    while (true) {
        // Yield frequently to check for runnable processes
        proc.Scheduler.yield();
    }
}

fn createInitProcess() void {

    // Allocate kernel stack for the process
    const kernel_stack = allocStack(4096);
    if (kernel_stack.len == 0) {
        while (true) {
            csr.wfi();
        }
    }

    // Create the init process
    if (proc.Scheduler.allocProcess("init", kernel_stack)) |init_proc| {
        // Set up process to run user mode shell
        setupUserProcess(init_proc);

        // Make the process runnable
        proc.Scheduler.makeRunnable(init_proc);
    } else {
        while (true) {
            csr.wfi();
        }
    }
}

fn setupUserProcess(process: *proc.Process) void {
    // This function will set up the process context to run the user shell
    // For now, we'll set up a basic context that will be used when the process
    // is scheduled to run
    _ = process; // Mark parameter as used

    // Get the init program code
    const _user_shell_start = @extern([*]const u8, .{ .name = "_user_shell_start" });
    const _user_shell_end = @extern([*]const u8, .{ .name = "_user_shell_end" });

    const start_addr = @intFromPtr(_user_shell_start);
    const end_addr = @intFromPtr(_user_shell_end);
    _ = start_addr;
    _ = end_addr;

    // For init process, we'll setup user mode execution through the trap system
    // The process context is already initialized for kernel-level context switching
    // User mode setup will be handled when the process runs

}

// Initialize PLIC for UART interrupts
fn initPLIC() void {

    // PLIC addresses for RISC-V virt machine
    const PLIC_BASE: u64 = 0x0c000000;
    const PLIC_PRIORITY = PLIC_BASE + 0x000000; // Interrupt source priority
    const PLIC_ENABLE = PLIC_BASE + 0x002000; // Interrupt enable bits
    const PLIC_THRESHOLD = PLIC_BASE + 0x200000; // Priority threshold

    // UART0 is interrupt source 10 in QEMU virt machine
    const UART_IRQ: u32 = 10;

    // Set UART interrupt priority to 1 (non-zero enables it)
    const priority_addr = @as(*volatile u32, @ptrFromInt(PLIC_PRIORITY + UART_IRQ * 4));
    priority_addr.* = 1;

    // Enable UART interrupt for hart 0, context 1 (supervisor mode)
    // For hart 0, context 1: enable register is at offset 0x2080
    const enable_addr = @as(*volatile u32, @ptrFromInt(PLIC_ENABLE + 0x80)); // Hart 0, context 1
    enable_addr.* = 1 << UART_IRQ;

    // Set priority threshold to 0 (accept all priorities)
    // For hart 0, context 1: threshold is at 0x201000
    const threshold_addr = @as(*volatile u32, @ptrFromInt(PLIC_THRESHOLD + 0x1000));
    threshold_addr.* = 0;
}
