// Process scheduler for Claudia kernel
// Manages process queues and scheduling decisions

const std = @import("std");
const csr = @import("../arch/riscv/csr.zig");
const uart = @import("../driver/uart/core.zig");
const trap = @import("../trap/core.zig");
const user = @import("../user/core.zig");
const defs = @import("abi");
const timer = @import("../time/timer.zig");
const config = @import("../config.zig");
const memory = @import("../memory/core.zig");
const virtual = @import("../memory/virtual.zig");

const types = @import("types.zig");
const context = @import("context.zig");
const syscalls = @import("syscalls.zig");

pub const Process = types.Process;
pub const ProcessState = types.ProcessState;
pub const PID = types.PID;
pub const WaitQ = types.WaitQ;
pub const Context = types.Context;

// External assembly function for context switching
extern fn context_switch(old_context: *Context, new_context: *Context) void;

// Simple process table
pub var process_table: [config.Process.MAX_PROCESSES]Process = undefined;
var next_pid: PID = 1;

// Current running process
pub var current_process: ?*Process = null;

// Ready queue (simple linked list)
var ready_queue_head: ?*Process = null;
var ready_queue_tail: ?*Process = null;

// Idle process resources
var idle_process: Process = undefined;
var idle_stack: [config.Process.CHILD_STACK_SIZE]u8 align(config.Process.STACK_ALIGNMENT) = undefined;

// Simple stack allocator for child processes
// Must be page-aligned for virtual memory mapping
const PAGE_SIZE = @import("../memory/types.zig").PAGE_SIZE;
var child_stack_pool: [config.Process.CHILD_POOL_SIZE][config.Process.CHILD_STACK_SIZE]u8 align(PAGE_SIZE) = undefined;
var child_stack_used: [config.Process.CHILD_POOL_SIZE]bool = [_]bool{false} ** config.Process.CHILD_POOL_SIZE;

// Trap frame pool for child processes
var child_frame_pool: [config.Process.CHILD_POOL_SIZE]trap.TrapFrame = undefined;
var child_frame_used: [config.Process.CHILD_POOL_SIZE]bool = [_]bool{false} ** config.Process.CHILD_POOL_SIZE;

// Helper to enqueue a process to the ready queue
// Must be called with interrupts disabled
fn enqueueProcess(proc: *Process) void {
    proc.next = null;
    if (ready_queue_tail) |tail| {
        tail.next = proc;
        ready_queue_tail = proc;
    } else {
        ready_queue_head = proc;
        ready_queue_tail = proc;
    }
}

// Initialize the process system
pub fn init() void {
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

    // Initialize idle process
    idle_process = Process.init(0, "idle", &idle_stack);
    idle_process.state = .EMBRYO;
    idle_process.is_kernel = true;
    context.initIdleContext(&idle_process);
}

// Allocate a new process
pub fn allocProcess(name: []const u8, stack: []u8) ?*Process {
    // Find unused slot
    for (&process_table) |*proc| {
        if (proc.state == .UNUSED) {
            proc.* = Process.init(next_pid, name, stack);
            next_pid += 1;

            // Re-initialize context with correct process pointer
            context.initProcessContext(proc);

            // Process is now ready to be made runnable
            proc.state = .EMBRYO;

            return proc;
        }
    }
    return null; // No free slots
}

pub fn makeRunnable(proc: *Process) void {
    if (proc.state == .RUNNABLE) {
        return; // Already runnable
    }

    if (types.isTerminated(proc)) {
        return; // Not eligible for scheduling
    }

    // Critical section - protect ready queue manipulation
    csr.disableInterrupts();
    defer csr.enableInterrupts();

    // Double-check not already in queue
    var p = ready_queue_head;
    while (p) |current| : (p = current.next) {
        if (current == proc) {
            return; // Already in queue
        }
    }

    proc.state = .RUNNABLE;
    enqueueProcess(proc);
}

// Remove and return next runnable process
pub fn dequeueRunnable() ?*Process {
    // Critical section - protect ready queue manipulation
    csr.disableInterrupts();
    defer csr.enableInterrupts();

    if (ready_queue_head) |head| {
        // Remove head from queue
        ready_queue_head = head.next;
        if (ready_queue_head == null) {
            ready_queue_tail = null;
        }
        head.next = null;
        return head;
    }
    return null;
}

// Core scheduling function - switches to next runnable process
// Switch address space to the given process
fn switchAddressSpace(proc: *Process) void {
    if (proc.page_table_ppn != 0) {
        // Process has its own page table
        const mode: u64 = 8; // Sv39
        const satp_value = (mode << 60) | (proc.page_table_ppn & 0xFFFFFFFFF);

        csr.writeSatp(satp_value);
        asm volatile ("sfence.vma" ::: "memory"); // Flush TLB
    }
    // If page_table_ppn is 0, keep using current page table (kernel or parent's)
}

// @param make_current_runnable: if true, adds current process to runnable queue
// @return: the newly scheduled process, or null if no switch occurred
pub fn schedule(make_current_runnable: bool) ?*Process {
    // Save current process state before switching
    if (current_process) |proc| {
        // Don't reschedule idle process unless something is runnable
        if (proc == &idle_process and ready_queue_head == null) {
            return proc;
        }

        // Optionally make current process runnable
        if (make_current_runnable and proc.state == .RUNNING and proc != &idle_process) {
            makeRunnable(proc);
        }

        // Find next runnable process
        if (dequeueRunnable()) |next| {
            next.state = .RUNNING;
            current_process = next;

            // Switch address space before context switch
            switchAddressSpace(next);
            context_switch(&proc.context, &next.context);

            return next;
        } else {
            // No other runnable process - switch to idle
            idle_process.state = .RUNNING;
            current_process = &idle_process;

            // Switch address space before context switch
            switchAddressSpace(&idle_process);
            context_switch(&proc.context, &idle_process.context);
            return &idle_process;
        }
    }

    // No current process - try to find one to run
    if (dequeueRunnable()) |next| {
        next.state = .RUNNING;
        current_process = next;
        return next;
    }

    // Nothing runnable - use idle process
    idle_process.state = .RUNNING;
    current_process = &idle_process;
    return &idle_process;
}

// Internal scheduler for exit() - must have current process
fn scheduleInternal() void {
    const proc = current_process orelse unreachable;

    // Find next runnable process
    if (dequeueRunnable()) |next| {
        next.state = .RUNNING;
        current_process = next;

        // Switch address space before context switch
        switchAddressSpace(next);
        // Context switch to next process
        context_switch(&proc.context, &next.context);
        // When we return here, this process has been rescheduled
    } else {
        // No runnable process - switch to idle process
        idle_process.state = .RUNNING;
        current_process = &idle_process;

        // Switch address space before context switch
        switchAddressSpace(&idle_process);
        // Context switch to idle process
        context_switch(&proc.context, &idle_process.context);
        // When we return here, this process has been rescheduled
    }
}

// Schedule next process without making current runnable
pub fn scheduleNext() void {
    const proc = current_process orelse return;

    // Find next runnable process
    if (dequeueRunnable()) |next| {
        next.state = .RUNNING;
        current_process = next;

        // Switch address space before context switch
        switchAddressSpace(next);
        // Context switch to next process
        context_switch(&proc.context, &next.context);
        // When we return here, this process has been rescheduled
    } else {
        // No runnable process - wait in a loop checking timers
        // Keep checking until this process or another becomes runnable
        while (proc.state == .SLEEPING and ready_queue_head == null) {
            csr.enableInterrupts();

            // Check timer periodically
            timer.tick();

            // Brief wait
            csr.wfi();
        }

        // Either this process was woken or another became runnable
        if (proc.state != .SLEEPING) {
            // This process was woken up, return to it
            return;
        }

        // Another process became runnable, schedule it
        if (ready_queue_head != null) {
            _ = schedule(false);
        }
    }
}

// Exit current process
pub fn exit(exit_code: i32) void {
    if (current_process) |proc| {
        proc.state = .ZOMBIE;
        proc.exit_code = exit_code;

        // Free resources if this is a forked child
        if (proc.parent != null) {
            // Free child's stack
            freeChildStack(proc.stack);

            // Free child's trap frame
            if (proc.user_frame) |frame| {
                freeChildTrapFrame(frame);
            }
        }

        // Free page table if process has its own (not kernel PT)
        if (proc.page_table_ppn != 0) {
            var page_table = virtual.PageTable{
                .root_ppn = proc.page_table_ppn,
                .debug_watchdog_active = false,
            };
            page_table.deinit();
            proc.page_table_ppn = 0;
        }

        // Wake parent if waiting
        if (proc.parent) |parent| {
            wakeup(@intFromPtr(parent));
        }

        // Don't set current_process to null before calling scheduleInternal()
        // scheduleInternal() needs it for context switching
        scheduleInternal(); // This will switch to another process and never return

        // This should never be reached
        unreachable;
    }
}

// Sleep current process on wait queue
pub fn sleepOn(wq: *WaitQ, proc: *Process) void {
    // Assert that we're sleeping the current process
    if (current_process != proc) {
        // This should not happen - only current process can sleep itself
        return;
    }

    // Critical section to prevent lost wakeups
    csr.disableInterrupts();

    proc.state = .SLEEPING;

    // Add to wait queue
    proc.next = wq.head;
    wq.head = proc;

    // Re-enable interrupts before scheduling
    // This ensures interrupts can wake us up
    csr.enableInterrupts();

    // Switch to another process
    if (schedule(false)) |_| {
        // We switched to another process and came back
        // This means we were woken up and rescheduled

        return;
    }

    // Check if proc pointer is in kernel range
    const proc_addr = @intFromPtr(proc);
    if (proc_addr < config.MemoryLayout.USER_KERNEL_BOUNDARY or proc_addr >= config.MemoryLayout.KERNEL_END_BOUNDARY) {
        // This should not happen - process table is in kernel BSS
        @panic("Process pointer outside kernel range");
    }

    // For now, just wait with interrupts enabled
    // Don't switch page tables - stay with current process's page table
    while (proc.state == .SLEEPING) {
        // Enable interrupts
        csr.enableInterrupts();

        // Check timers periodically
        timer.tick();

        // Check if any process became runnable
        if (ready_queue_head != null) {
            // Resume normal scheduling
            _ = schedule(false);
            return;
        }

        // Wait for interrupt
        csr.wfi();
    }
}

// Wake processes sleeping on a specific wait channel
pub fn wakeup(chan: usize) void {
    for (&process_table) |*proc| {
        if (proc.state == .SLEEPING and @intFromPtr(proc) == chan) {
            makeRunnable(proc);
        }
    }
}

// Wake all processes on wait queue
pub fn wakeAll(wq: *WaitQ) void {
    csr.disableInterrupts();

    var count: u32 = 0;
    while (wq.head) |proc| {
        count += 1;
        wq.head = proc.next;
        proc.next = null;
        // makeRunnable will set state to RUNNABLE
        makeRunnable(proc);
    }

    csr.enableInterrupts();
}

// Main scheduler loop - handles all scheduling and idle
pub fn run() noreturn {
    // Find and run the first process
    if (dequeueRunnable()) |proc| {
        proc.state = .RUNNING;
        current_process = proc;

        // Jump to the process entry point
        context.processEntryPointWithProc(proc);
    }

    // No processes to run - just idle
    while (true) {
        csr.enableInterrupts();

        // Check timer periodically
        timer.tick();

        // Check if any process became runnable
        if (ready_queue_head != null) {
            if (dequeueRunnable()) |proc| {
                proc.state = .RUNNING;
                current_process = proc;
                context.processEntryPointWithProc(proc);
            }
        }

        csr.wfi();
    }
}

// Get current running process
pub fn getCurrentProcess() ?*Process {
    return current_process;
}

// Request scheduler to run (e.g., from timer interrupt)
pub fn yield() void {
    const proc = current_process orelse return;

    if (proc.state != .RUNNING) {
        return; // Not in RUNNING state
    }

    // Special handling for idle process
    if (proc == &idle_process) {
        // Idle process only yields if there's something to run
        if (ready_queue_head != null) {
            _ = schedule(false); // Yield to runnable process
        }
        return;
    }

    // Use the unified schedule function
    _ = schedule(true);
}

// Clean up zombie processes (should be called periodically)
pub fn reapZombies() void {
    for (&process_table) |*proc| {
        if (proc.state == .ZOMBIE) {
            // Mark as unused so it can be reused
            proc.state = .UNUSED;
            proc.pid = 0;
        }
    }
}

// Allocate stack for child process
pub fn allocateChildStack() ?[]u8 {
    for (&child_stack_used, 0..) |*used, i| {
        if (!used.*) {
            used.* = true;
            return child_stack_pool[i][0..];
        }
    }
    return null; // No free stacks
}

// Free child stack (called when process exits)
pub fn freeChildStack(stack: []u8) void {
    for (&child_stack_pool, &child_stack_used) |*pool_stack, *used| {
        if (stack.ptr == pool_stack.ptr) {
            used.* = false;
            break;
        }
    }
}

// Allocate trap frame for child process
pub fn allocateChildTrapFrame() ?*trap.TrapFrame {
    for (&child_frame_used, 0..) |*used, i| {
        if (!used.*) {
            used.* = true;
            return &child_frame_pool[i];
        }
    }
    return null; // No free frames
}

// Free child trap frame (called when process exits)
pub fn freeChildTrapFrame(frame: *trap.TrapFrame) void {
    for (&child_frame_pool, &child_frame_used) |*pool_frame, *used| {
        if (frame == pool_frame) {
            used.* = false;
            break;
        }
    }
}

pub fn idleLoop() noreturn {
    while (true) {
        // Enable interrupts to receive timer/device interrupts
        csr.enableInterrupts();

        // Check timers that might wake sleeping processes
        timer.tick();

        // Check if any process became runnable
        if (ready_queue_head != null) {
            // Something is runnable, yield to scheduler
            yield();
        }

        // Wait for interrupt
        csr.wfi();
    }
}
