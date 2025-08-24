// Kernel core initialization and system startup
// Coordinates initialization of all kernel subsystems

const std = @import("std");

// Architecture specific
const csr = @import("arch/riscv/csr.zig");

// Core subsystems
const memory = @import("memory/core.zig");
const proc = @import("process/core.zig");
const trap = @import("trap/core.zig");
const file = @import("file/core.zig");
const user = @import("user/core.zig");
const vfs = @import("fs/vfs.zig");

// Drivers
const uart = @import("driver/uart/core.zig");
const plic = @import("driver/plic.zig");

// Boot-time memory allocation
// Simple stack allocator for initial kernel processes
// This is used before the heap is fully initialized
var boot_stack_memory: [4096 * 4]u8 = undefined;
var boot_stack_offset: usize = 0;

fn allocBootStack(size: usize) []u8 {
    const aligned_size = (size + 7) & ~@as(usize, 7); // 8-byte align
    if (boot_stack_offset + aligned_size > boot_stack_memory.len) {
        return &[_]u8{}; // Out of memory
    }

    const stack = boot_stack_memory[boot_stack_offset .. boot_stack_offset + aligned_size];
    boot_stack_offset += aligned_size;
    return stack;
}

// Main kernel initialization
pub fn init() noreturn {
    // Phase 1: Early initialization (no heap, no MMU)
    initEarlyBoot();

    // Phase 2: Memory system initialization
    initMemorySystem();

    // Phase 3: Core subsystems
    initCoreSubsystems();

    // Phase 4: Create initial processes
    createInitialProcesses();

    // Phase 5: Start scheduling
    proc.Scheduler.run(); // Never returns
}

fn initEarlyBoot() void {
    // Initialize UART for early debugging
    uart.init();

    // Initialize physical memory allocator
    memory.init();
}

fn initMemorySystem() void {
    // Initialize virtual memory
    memory.initVirtual() catch {
        halt("Failed to initialize virtual memory");
    };

    // Initialize kernel heap before enabling MMU
    const kalloc = @import("memory/kalloc.zig");
    kalloc.init() catch {
        halt("Failed to initialize kernel heap");
    };

    // Enable MMU
    memory.enableMMU();
}

fn initCoreSubsystems() void {
    // Initialize file system first (before VFS)
    file.FileTable.init();

    // Initialize VFS after file system
    vfs.init();

    // Initialize trap handling
    trap.init();

    // Initialize interrupt system
    initInterrupts();

    // Initialize user subsystem
    user.init();

    // Initialize process scheduler
    proc.Scheduler.init();
}

fn initInterrupts() void {
    // Enable supervisor external interrupts for UART
    csr.enableInterrupts();

    // Enable external interrupts in SIE
    csr.csrs(csr.CSR.sie, 1 << 9); // SEIE bit

    // Initialize PLIC for external interrupts
    plic.init();
}

fn createInitialProcesses() void {
    // Create the init process (PID 1)
    createInitProcess();
}

fn halt(msg: []const u8) noreturn {
    uart.puts("KERNEL PANIC: ");
    uart.puts(msg);
    uart.puts("\n");
    while (true) {
        csr.wfi();
    }
}

// Process creation
fn createInitProcess() void {

    // Allocate kernel stack for the process
    const kernel_stack = allocBootStack(4096);
    if (kernel_stack.len == 0) {
        halt("Failed to allocate stack for init process");
    }

    // Create the init process
    if (proc.Scheduler.allocProcess("init", kernel_stack)) |init_proc| {
        // Set up process to run user mode shell
        setupUserProcess(init_proc);

        // Make the process runnable
        proc.Scheduler.makeRunnable(init_proc);
    } else {
        halt("Failed to create init process");
    }
}

fn setupUserProcess(process: *proc.Process) void {
    // Mark process for user mode execution
    // The actual user mode setup happens when the process runs
    _ = process;
}

// Idle process support
pub fn idleLoop() noreturn {
    // Simple idle loop - just yield CPU
    while (true) {
        csr.wfi();
    }
}
