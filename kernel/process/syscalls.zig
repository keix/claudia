const std = @import("std");
const csr = @import("../arch/riscv/csr.zig");
const uart = @import("../driver/uart/core.zig");
const trap = @import("../trap/core.zig");
const user = @import("../user/core.zig");
const defs = @import("abi");
const config = @import("../config.zig");
const virtual = @import("../memory/virtual.zig");
const page_size = @import("../memory/types.zig").PAGE_SIZE;

const types = @import("types.zig");
const scheduler = @import("scheduler.zig");
const context = @import("context.zig");

pub const Process = types.Process;
pub const Context = types.Context;

const child_return_to_user = @extern(*const fn (*trap.TrapFrame) callconv(.C) noreturn, .{ .name = "child_return_to_user" });

// RISC-V specific constants for process management
const ECALL_INSTRUCTION_SIZE: u64 = 4; // Size of ecall instruction
const SPIE_BIT: u6 = 5; // Supervisor Previous Interrupt Enable
const SV39_MODE: u64 = 8; // 39-bit virtual addressing mode
const SATP_MODE_SHIFT: u6 = 60; // Position of MODE field in SATP
const SATP_PPN_MASK: u64 = 0xFFFFFFFFF; // Mask for Physical Page Number

// Allocate resources for a new child process
// Returns both the process structure and its stack for proper cleanup on error
fn allocateChildResources() !struct { child: *Process, stack: []u8 } {
    const child_stack = scheduler.allocateChildStack() orelse return error.OutOfMemory;
    errdefer scheduler.freeChildStack(child_stack);

    const child = scheduler.allocProcess("child", child_stack) orelse return error.ProcessTableFull;

    return .{ .child = child, .stack = child_stack };
}

// Create and setup page table for child process
// This includes:
//   1. Creating new page table
//   2. Copying kernel mappings
//   3. Cloning parent's user space
//   4. Mapping child's kernel stack
fn setupChildPageTable(parent: *Process, child: *Process) !void {
    var child_pt = virtual.PageTable{ .root_ppn = 0 };
    try child_pt.init();
    errdefer child_pt.deinit();

    try virtual.buildKernelGlobalMappings(&child_pt);

    // Get parent's page table - handle case where parent uses kernel PT
    var parent_pt = virtual.PageTable{ .root_ppn = parent.page_table_ppn };
    if (parent_pt.root_ppn == 0) {
        const satp = csr.readSatp();
        parent_pt.root_ppn = (satp >> 44) & SATP_PPN_MASK;
    }

    try virtual.cloneUserSpace(&parent_pt, &child_pt);

    // Map child's kernel stack (identity mapped in kernel space)
    const child_stack_start = @intFromPtr(child.stack.ptr);
    const child_stack_pages = (child.stack.len + page_size - 1) / page_size;

    for (0..child_stack_pages) |i| {
        const vaddr = child_stack_start + i * page_size;
        const paddr = vaddr;
        try child_pt.map(vaddr, paddr, virtual.PTE_R | virtual.PTE_W | virtual.PTE_G);
    }

    child.page_table_ppn = child_pt.root_ppn;
}

// Setup execution context for child process
// Child will return from fork() with value 0
fn setupChildContext(parent: *Process, child: *Process) !void {
    const parent_frame = parent.user_frame orelse return error.NoUserFrame;

    const child_frame = scheduler.allocateChildTrapFrame() orelse return error.OutOfMemory;
    // Copy parent's trap frame and adjust for child
    child_frame.* = parent_frame.*;
    child_frame.a0 = 0; // Child returns 0 from fork
    child_frame.gp = 0; // Clear GP to prevent GP-relative addressing issues
    child_frame.sepc = parent_frame.sepc + ECALL_INSTRUCTION_SIZE; // Skip ecall

    child.user_frame = child_frame;
    child.context = Context.zero();

    // Setup kernel context for child
    child.context.ra = @intFromPtr(&forkedChildReturn); // Where to start execution
    child.context.sp = @intFromPtr(child.stack.ptr) + child.stack.len - config.Process.STACK_ALIGNMENT;
    child.context.s0 = @intFromPtr(child); // Process pointer in s0
    // Note: a0 return value (0 for child) is already set in child_frame.a0 above
    // satp will be set by scheduler when switching to this process based on child.page_table_ppn
    // sstatus interrupt enable will be managed by scheduler
}

// Fork system call - create a copy of the current process
// Parent returns child PID, child returns 0
// Uses copy-on-write semantics for efficiency (if implemented)
pub fn fork() isize {
    // Clean up any zombie processes first to free slots
    scheduler.reapZombies();

    // Disable interrupts during critical fork operations
    const saved_sie = csr.csrrc(csr.CSR.sstatus, csr.SSTATUS.SIE);
    defer {
        if ((saved_sie & csr.SSTATUS.SIE) != 0) {
            _ = csr.csrrs(csr.CSR.sstatus, csr.SSTATUS.SIE);
        }
    }

    const parent = scheduler.getCurrentProcess() orelse return defs.ESRCH;

    // Allocate child process and resources
    const resources = allocateChildResources() catch |err| switch (err) {
        error.OutOfMemory => return defs.ENOMEM,
        error.ProcessTableFull => return defs.EAGAIN,
    };
    const child = resources.child;

    child.parent = parent;
    child.heap_start = parent.heap_start;
    child.heap_end = parent.heap_end;

    // Setup page table for child
    setupChildPageTable(parent, child) catch {
        // Cleanup on error
        if (child.page_table_ppn != 0) {
            var pt = virtual.PageTable{ .root_ppn = child.page_table_ppn };
            pt.deinit();
        }
        if (child.user_frame) |frame| scheduler.freeChildTrapFrame(frame);
        return defs.ENOMEM;
    };

    // Setup context for child
    setupChildContext(parent, child) catch |err| {
        // Cleanup on error
        var pt = virtual.PageTable{ .root_ppn = child.page_table_ppn };
        pt.deinit();
        return switch (err) {
            error.NoUserFrame => defs.EINVAL,
            error.OutOfMemory => defs.ENOMEM,
        };
    };

    // Ensure all memory writes are visible before making child runnable
    asm volatile ("fence rw, rw" ::: "memory");
    scheduler.makeRunnable(child);

    return @as(isize, @intCast(child.pid));
}

pub fn exec(filename: []const u8, args: []const u8) isize {
    _ = args;
    const current = scheduler.getCurrentProcess() orelse return -1;

    // For simplicity, only support "shell" for now
    if (std.mem.eql(u8, filename, "shell") or std.mem.eql(u8, filename, "/bin/shell")) {
        // Replace current process with shell - this does not return on success
        execShell(current);
    } else {
        return -1;
    }
}

// Entry point for forked child processes
// Retrieves trap frame and returns to user mode
pub fn forkedChildReturn() noreturn {
    const child_proc = scheduler.getCurrentProcess() orelse {
        while (true) {
            csr.wfi();
        }
    };

    const frame = child_proc.user_frame orelse {
        while (true) {
            csr.wfi();
        }
    };

    child_return_to_user(frame);
}

fn execShell(_: *Process) noreturn {
    const _user_shell_start = @extern([*]const u8, .{ .name = "_user_shell_start" });
    const _user_shell_end = @extern([*]const u8, .{ .name = "_user_shell_end" });

    const start_addr = @intFromPtr(_user_shell_start);
    const end_addr = @intFromPtr(_user_shell_end);
    const code_size = end_addr - start_addr;

    if (code_size > 0 and code_size < config.Process.MAX_SHELL_SIZE) {
        const code = @as([*]const u8, @ptrFromInt(start_addr))[0..code_size];

        user.executeUserProgram(code, "") catch {
            scheduler.exit(-1);
        };

        scheduler.exit(-1);
    } else {
        scheduler.exit(-1);
    }
    unreachable;
}

pub fn sys_wait4(pid: i32, status: ?*i32, options: i32, rusage: ?*anyopaque) isize {
    _ = pid;
    _ = status;
    _ = options;
    _ = rusage;

    const proc = scheduler.getCurrentProcess() orelse {
        return -defs.ESRCH;
    };

    while (true) {
        for (&scheduler.process_table) |*p| {
            if (p.state == .ZOMBIE and p.parent == proc) {
                const child_pid = @as(isize, @intCast(p.pid));

                p.state = .UNUSED;
                p.parent = null;

                return child_pid;
            }
        }

        var has_child = false;
        for (&scheduler.process_table) |*p| {
            if (p.parent == proc and p.state != .UNUSED) {
                has_child = true;
                break;
            }
        }
        if (!has_child) return -defs.ECHILD;

        proc.state = .SLEEPING;
        scheduler.yield();
    }
}
