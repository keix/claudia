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

extern fn context_switch(old_context: *Context, new_context: *Context) void;

pub var process_table: [config.Process.MAX_PROCESSES]Process = undefined;

const INITIAL_PID: PID = 1;
var next_pid: PID = INITIAL_PID;

pub var current_process: ?*Process = null;

var ready_queue_head: ?*Process = null;
var ready_queue_tail: ?*Process = null;

var idle_process: Process = undefined;
var idle_stack: [config.Process.CHILD_STACK_SIZE]u8 align(config.Process.STACK_ALIGNMENT) = undefined;

const PAGE_SIZE = @import("../memory/types.zig").PAGE_SIZE;
var child_stack_pool: [config.Process.CHILD_POOL_SIZE][config.Process.CHILD_STACK_SIZE]u8 align(PAGE_SIZE) = undefined;
var child_stack_used: [config.Process.CHILD_POOL_SIZE]bool = [_]bool{false} ** config.Process.CHILD_POOL_SIZE;

var child_frame_pool: [config.Process.CHILD_POOL_SIZE]trap.TrapFrame = undefined;
var child_frame_used: [config.Process.CHILD_POOL_SIZE]bool = [_]bool{false} ** config.Process.CHILD_POOL_SIZE;

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

pub fn init() void {
    for (&process_table) |*proc| {
        proc.state = .UNUSED;
        proc.pid = 0;
        proc.next = null;
    }

    current_process = null;
    ready_queue_head = null;
    ready_queue_tail = null;
    next_pid = INITIAL_PID;

    idle_process = Process.init(0, "idle", &idle_stack);
    idle_process.state = .EMBRYO;
    idle_process.is_kernel = true;
    context.initIdleContext(&idle_process);
}

const PID_INCREMENT: PID = 1;

pub fn allocProcess(name: []const u8, stack: []u8) ?*Process {
    for (&process_table) |*proc| {
        if (proc.state == .UNUSED) {
            proc.* = Process.init(next_pid, name, stack);
            next_pid += PID_INCREMENT;

            context.initProcessContext(proc);

            proc.state = .EMBRYO;

            return proc;
        }
    }
    return null;
}

pub fn makeRunnable(proc: *Process) void {
    if (proc.state == .RUNNABLE) {
        return;
    }

    if (types.isTerminated(proc)) {
        return;
    }

    csr.disableInterrupts();
    defer csr.enableInterrupts();

    var p = ready_queue_head;
    while (p) |current| : (p = current.next) {
        if (current == proc) {
            return;
        }
    }

    proc.state = .RUNNABLE;
    enqueueProcess(proc);
}

pub fn dequeueRunnable() ?*Process {
    csr.disableInterrupts();
    defer csr.enableInterrupts();

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

// Constants for RISC-V Sv39 page table format
const SV39_MODE: u64 = 8; // Sv39 mode value for SATP
const SATP_MODE_SHIFT: u6 = 60; // MODE field position in SATP
const SATP_PPN_MASK: u64 = 0xFFFFFFFFF; // Mask for 44-bit PPN field

// Mark process as current running process
fn makeProcessCurrent(proc: *Process) void {
    proc.state = .RUNNING;
    current_process = proc;
}

// Perform full context switch from current to next process
// This includes: state update, address space switch, and register context switch
fn contextSwitch(current: *Process, next: *Process) void {
    makeProcessCurrent(next);
    switchAddressSpace(next);
    context_switch(&current.context, &next.context);
}

// Switch to process's address space by updating SATP register
fn switchAddressSpace(proc: *Process) void {
    if (proc.page_table_ppn != 0) {
        const satp_value = (SV39_MODE << SATP_MODE_SHIFT) | (proc.page_table_ppn & SATP_PPN_MASK);

        csr.writeSatp(satp_value);
        asm volatile ("sfence.vma" ::: "memory");
    }
}

// Core scheduling function - select and switch to next process
// @param make_current_runnable: whether to re-queue current process
// @return: the newly scheduled process
pub fn schedule(make_current_runnable: bool) ?*Process {
    if (current_process) |proc| {
        if (proc == &idle_process and ready_queue_head == null) {
            return proc;
        }

        if (make_current_runnable and proc.state == .RUNNING and proc != &idle_process) {
            makeRunnable(proc);
        }

        if (dequeueRunnable()) |next| {
            contextSwitch(proc, next);
            return next;
        } else {
            contextSwitch(proc, &idle_process);
            return &idle_process;
        }
    }

    if (dequeueRunnable()) |next| {
        makeProcessCurrent(next);
        return next;
    }

    makeProcessCurrent(&idle_process);
    return &idle_process;
}

// Internal scheduler for process exit - current process won't return
fn scheduleInternal() void {
    const proc = current_process orelse unreachable;

    if (dequeueRunnable()) |next| {
        contextSwitch(proc, next);
    } else {
        contextSwitch(proc, &idle_process);
    }
}

// Schedule next process without making current runnable
// Used when current process is sleeping
pub fn scheduleNext() void {
    const proc = current_process orelse return;

    if (dequeueRunnable()) |next| {
        contextSwitch(proc, next);
    } else {
        while (proc.state == .SLEEPING and ready_queue_head == null) {
            waitForRunnableProcess();
        }

        if (proc.state != .SLEEPING) {
            return;
        }

        if (ready_queue_head != null) {
            _ = schedule(false);
        }
    }
}

pub fn exit(exit_code: i32) void {
    if (current_process) |proc| {
        proc.state = .ZOMBIE;
        proc.exit_code = exit_code;

        if (proc.parent != null) {
            freeChildStack(proc.stack);

            if (proc.user_frame) |frame| {
                freeChildTrapFrame(frame);
            }
        }

        if (proc.page_table_ppn != 0) {
            var page_table = virtual.PageTable{
                .root_ppn = proc.page_table_ppn,
            };
            page_table.deinit();
            proc.page_table_ppn = 0;
        }

        if (proc.parent) |parent| {
            wakeup(@intFromPtr(parent));
        }

        scheduleInternal();
        unreachable;
    }
}

pub fn sleepOn(wq: *WaitQ, proc: *Process) void {
    if (current_process != proc) {
        return;
    }

    csr.disableInterrupts();

    proc.state = .SLEEPING;

    proc.next = wq.head;
    wq.head = proc;

    csr.enableInterrupts();

    if (schedule(false)) |_| {
        return;
    }

    const proc_addr = @intFromPtr(proc);
    if (proc_addr < config.MemoryLayout.USER_KERNEL_BOUNDARY or proc_addr >= config.MemoryLayout.KERNEL_END_BOUNDARY) {
        @panic("Process pointer outside kernel range");
    }

    while (proc.state == .SLEEPING) {
        waitForRunnableProcess();

        if (ready_queue_head != null) {
            _ = schedule(false);
            return;
        }
    }
}

pub fn wakeup(chan: usize) void {
    for (&process_table) |*proc| {
        if (proc.state == .SLEEPING and @intFromPtr(proc) == chan) {
            makeRunnable(proc);
        }
    }
}

pub fn wakeAll(wq: *WaitQ) void {
    csr.disableInterrupts();

    while (wq.head) |proc| {
        wq.head = proc.next;
        proc.next = null;
        makeRunnable(proc);
    }

    csr.enableInterrupts();
}

// Main scheduler entry point - starts scheduling the first process
pub fn run() noreturn {
    if (dequeueRunnable()) |proc| {
        makeProcessCurrent(proc);
        context.processEntryPointWithProc(proc);
    }

    while (true) {
        waitForRunnableProcess();

        if (ready_queue_head != null) {
            if (dequeueRunnable()) |proc| {
                makeProcessCurrent(proc);
                context.processEntryPointWithProc(proc);
            }
        }
    }
}

pub fn getCurrentProcess() ?*Process {
    return current_process;
}

pub fn yield() void {
    const proc = current_process orelse return;

    if (proc.state != .RUNNING) {
        return;
    }

    if (proc == &idle_process) {
        if (ready_queue_head != null) {
            _ = schedule(false);
        }
        return;
    }

    _ = schedule(true);
}

pub fn reapZombies() void {
    for (&process_table) |*proc| {
        if (proc.state == .ZOMBIE) {
            proc.state = .UNUSED;
            proc.pid = 0;
        }
    }
}

// Generic pool allocator for fixed-size resources
fn allocateFromPool(comptime T: type, pool: []T, used: []bool) ?*T {
    for (used, 0..) |*is_used, i| {
        if (!is_used.*) {
            is_used.* = true;
            return &pool[i];
        }
    }
    return null;
}

fn freeFromPool(comptime T: type, pool: []T, used: []bool, item: *T) void {
    for (pool, used) |*pool_item, *is_used| {
        if (item == pool_item) {
            is_used.* = false;
            break;
        }
    }
}

// Wait for any process to become runnable
// Enables interrupts and checks timers while waiting
fn waitForRunnableProcess() void {
    csr.enableInterrupts();
    timer.tick();
    csr.wfi();
}

pub fn allocateChildStack() ?[]u8 {
    const stack = allocateFromPool([config.Process.CHILD_STACK_SIZE]u8, &child_stack_pool, &child_stack_used);
    if (stack) |s| {
        return s[0..];
    }
    return null;
}

pub fn freeChildStack(stack: []u8) void {
    for (&child_stack_pool, &child_stack_used) |*pool_stack, *used| {
        if (stack.ptr == pool_stack.ptr) {
            used.* = false;
            break;
        }
    }
}

pub fn allocateChildTrapFrame() ?*trap.TrapFrame {
    return allocateFromPool(trap.TrapFrame, &child_frame_pool, &child_frame_used);
}

pub fn freeChildTrapFrame(frame: *trap.TrapFrame) void {
    freeFromPool(trap.TrapFrame, &child_frame_pool, &child_frame_used, frame);
}

// Idle process loop - runs when no other process is runnable
// Continuously checks for runnable processes while saving power
pub fn idleLoop() noreturn {
    while (true) {
        waitForRunnableProcess();

        if (ready_queue_head != null) {
            yield();
        }
    }
}
