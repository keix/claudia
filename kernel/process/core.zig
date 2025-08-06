// Process management for Claudia kernel
// RISC-V specific process structures and scheduling

const std = @import("std");
const csr = @import("../arch/riscv/csr.zig");
const uart = @import("../driver/uart/core.zig");

// Process ID type
pub const PID = u32;

// Process states
pub const ProcessState = enum {
    UNUSED, // Slot not in use
    EMBRYO, // Being created
    SLEEPING, // Sleeping on a wait channel
    RUNNABLE, // Ready to run
    RUNNING, // Currently running
    ZOMBIE, // Terminated but not yet cleaned up
};

// RISC-V CPU context for process switching
pub const Context = struct {
    // General purpose registers
    ra: u64, // x1 - return address
    sp: u64, // x2 - stack pointer
    gp: u64, // x3 - global pointer
    tp: u64, // x4 - thread pointer
    t0: u64, // x5 - temporary
    t1: u64, // x6 - temporary
    t2: u64, // x7 - temporary
    s0: u64, // x8 - saved register / frame pointer
    s1: u64, // x9 - saved register
    a0: u64, // x10 - argument/return value
    a1: u64, // x11 - argument/return value
    a2: u64, // x12 - argument
    a3: u64, // x13 - argument
    a4: u64, // x14 - argument
    a5: u64, // x15 - argument
    a6: u64, // x16 - argument
    a7: u64, // x17 - argument
    s2: u64, // x18 - saved register
    s3: u64, // x19 - saved register
    s4: u64, // x20 - saved register
    s5: u64, // x21 - saved register
    s6: u64, // x22 - saved register
    s7: u64, // x23 - saved register
    s8: u64, // x24 - saved register
    s9: u64, // x25 - saved register
    s10: u64, // x26 - saved register
    s11: u64, // x27 - saved register
    t3: u64, // x28 - temporary
    t4: u64, // x29 - temporary
    t5: u64, // x30 - temporary
    t6: u64, // x31 - temporary

    // Control and status registers
    sepc: u64, // Supervisor exception program counter
    sstatus: u64, // Supervisor status register

    pub fn zero() Context {
        return std.mem.zeroes(Context);
    }
};

// Process control block
pub const Process = struct {
    pid: PID, // Process ID
    state: ProcessState, // Process state
    context: Context, // CPU context for switching
    stack: []u8, // Process stack
    name: [16]u8, // Process name (null-terminated)
    parent: ?*Process, // Parent process
    exit_code: i32, // Exit code when zombie

    // Simple linked list for process queue
    next: ?*Process,

    pub fn init(pid: PID, name: []const u8, stack: []u8) Process {
        var proc = Process{
            .pid = pid,
            .state = .EMBRYO,
            .context = Context.zero(),
            .stack = stack,
            .name = std.mem.zeroes([16]u8),
            .parent = null,
            .exit_code = 0,
            .next = null,
        };

        // Copy name (max 15 chars + null terminator)
        const copy_len = @min(name.len, 15);
        @memcpy(proc.name[0..copy_len], name[0..copy_len]);
        proc.name[copy_len] = 0;

        return proc;
    }

    pub fn getName(self: *const Process) []const u8 {
        const len = std.mem.indexOfScalar(u8, &self.name, 0) orelse self.name.len;
        return self.name[0..len];
    }
};

// Simple process table
const MAX_PROCESSES = 64;
var process_table: [MAX_PROCESSES]Process = undefined;
var next_pid: PID = 1;

// Current running process
var current_process: ?*Process = null;

// Ready queue (simple linked list)
var ready_queue_head: ?*Process = null;
var ready_queue_tail: ?*Process = null;

// Process scheduler
pub const Scheduler = struct {
    // Initialize the process system
    pub fn init() void {
        uart.debug("Initializing process scheduler\n");

        // Initialize process table
        for (&process_table) |*proc| {
            proc.state = .UNUSED;
            proc.pid = 0;
            proc.next = null;
        }

        // Reset global state
        current_process = null;
        ready_queue_head = null;
        ready_queue_tail = null;
        next_pid = 1;

        uart.debug("Process scheduler initialized\n");
    }

    // Allocate a new process
    pub fn allocProcess(name: []const u8, stack: []u8) ?*Process {
        // Find unused slot
        for (&process_table) |*proc| {
            if (proc.state == .UNUSED) {
                proc.* = Process.init(next_pid, name, stack);
                next_pid += 1;

                uart.debug("Allocated process ");
                uart.puts(proc.getName());
                uart.puts(" with PID ");
                uart.putHex(proc.pid);
                uart.puts("\n");

                return proc;
            }
        }
        return null; // No free slots
    }

    // Add process to ready queue
    pub fn makeRunnable(proc: *Process) void {
        if (proc.state != .EMBRYO and proc.state != .SLEEPING) {
            return; // Process already runnable or running
        }

        proc.state = .RUNNABLE;
        proc.next = null;

        if (ready_queue_tail) |tail| {
            tail.next = proc;
            ready_queue_tail = proc;
        } else {
            ready_queue_head = proc;
            ready_queue_tail = proc;
        }

        uart.debug("Made process ");
        uart.puts(proc.getName());
        uart.puts(" runnable\n");
    }

    // Remove and return next runnable process
    pub fn dequeueRunnable() ?*Process {
        if (ready_queue_head) |head| {
            ready_queue_head = head.next;
            if (ready_queue_head == null) {
                ready_queue_tail = null;
            }
            head.next = null;
            return head;
        }
        return null;
    }

    // Simple round-robin scheduler
    // Returns the process to switch to, or null if none available
    pub fn schedule() ?*Process {
        // Save current process context if running
        if (current_process) |current| {
            if (current.state == .RUNNING) {
                current.state = .RUNNABLE;
                makeRunnable(current);
            }
        }

        // Get next runnable process
        if (dequeueRunnable()) |next_proc| {
            next_proc.state = .RUNNING;
            current_process = next_proc;

            uart.debug("Switching to process ");
            uart.puts(next_proc.getName());
            uart.puts("\n");

            // TODO: Actual context switch
            switchToProcess(next_proc);
            return next_proc;
        } else {
            // No runnable processes, idle
            current_process = null;
            uart.debug("No runnable processes, idling\n");
            return null;
        }
    }

    // Get current running process
    pub fn getCurrentProcess() ?*Process {
        return current_process;
    }

    // Exit current process
    pub fn exit(exit_code: i32) void {
        if (current_process) |proc| {
            proc.state = .ZOMBIE;
            proc.exit_code = exit_code;

            uart.debug("Process ");
            uart.puts(proc.getName());
            uart.puts(" exited with code ");
            uart.putHex(@as(u64, @bitCast(@as(i64, exit_code))));
            uart.puts("\n");

            current_process = null;
            _ = schedule(); // Find next process to run
        }
    }

    // Main scheduler loop - handles all scheduling and idle
    pub fn run() noreturn {
        uart.debug("Starting scheduler main loop\n");

        while (true) {
            // Try to schedule a process
            _ = schedule();

            // If no process is running, enter idle state
            if (current_process == null) {
                // No runnable processes, wait for interrupt
                csr.wfi();
            }

            // In a real implementation, this would be driven by:
            // - Timer interrupts (for preemptive scheduling)
            // - I/O completion interrupts
            // - System calls that block/unblock processes
            // - Inter-process communication
        }
    }

    // Request scheduler to run (e.g., from timer interrupt)
    pub fn yield() void {
        // In a real implementation, this would be called from:
        // - Timer interrupt handler
        // - System call that should yield CPU
        // - Voluntary yield from current process
        schedule();
    }
};

// Context switching (placeholder)
fn switchToProcess(proc: *Process) void {
    // TODO: Implement actual RISC-V context switching
    // This would involve:
    // 1. Save current CPU state to current_process.context
    // 2. Load proc.context to CPU registers
    // 3. Update satp for virtual memory if needed
    // 4. Return to user mode if user process

    uart.debug("Context switch to ");
    uart.puts(proc.getName());
    uart.puts(" (placeholder)\n");
}
