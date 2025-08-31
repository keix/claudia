// System call implementations for process management
// Fork, exec, and exit system calls

const std = @import("std");
const csr = @import("../arch/riscv/csr.zig");
const uart = @import("../driver/uart/core.zig");
const trap = @import("../trap/core.zig");
const user = @import("../user/core.zig");
const defs = @import("abi");
const config = @import("../config.zig");

const types = @import("types.zig");
const scheduler = @import("scheduler.zig");
const context = @import("context.zig");

pub const Process = types.Process;
pub const Context = types.Context;

// External assembly function for returning to user mode
const child_return_to_user = @extern(*const fn (*trap.TrapFrame) callconv(.C) noreturn, .{ .name = "child_return_to_user" });

// Fork current process (simplified implementation)
pub fn fork() isize {
    const parent = scheduler.getCurrentProcess() orelse return defs.ESRCH;

    // Allocate static kernel stack for child (simple allocator)
    const child_stack = scheduler.allocateChildStack() orelse return defs.ENOMEM;

    // Create child process
    const child = scheduler.allocProcess("child", child_stack) orelse return defs.EAGAIN;

    // Copy parent process context - but child should not go to processEntryPoint
    // Instead, child should resume from the syscall return point
    child.parent = parent;

    // CRITICAL: For now, child shares parent's page table
    // This is a simplified fork - proper fork would copy the page table
    // The child MUST call exec() to get its own page table with kernel mappings

    // Copy user mode trap frame if it exists
    if (parent.user_frame) |parent_frame| {
        // Allocate independent trap frame for child
        const child_frame = scheduler.allocateChildTrapFrame() orelse return -1;
        child_frame.* = parent_frame.*;
        child_frame.a0 = 0; // Child returns 0 from fork
        child_frame.gp = 0; // Ensure GP is 0 to prevent GP-relative addressing

        // CRITICAL: Adjust sepc to skip the ecall instruction
        // The parent's sepc will be incremented by the trap handler
        // but the child needs to return to the instruction after ecall
        child_frame.sepc = parent_frame.sepc + 4;

        child.user_frame = child_frame;

        // Set up child context - start fresh
        child.context = Context.zero();

        // Set up critical registers for child
        child.context.ra = @intFromPtr(&forkedChildReturn);
        child.context.sp = @intFromPtr(child.stack.ptr) + child.stack.len - config.Process.STACK_ALIGNMENT;
        child.context.s0 = @intFromPtr(child); // Process pointer in s0
        child.context.a0 = 0; // Return value for fork (child returns 0)

        // CRITICAL: Set supervisor mode in context for proper return
        // SPP=1 (supervisor), SPIE=1 (interrupts enabled after sret)
        child.context.sstatus = (1 << 8) | (1 << 5); // SPP | SPIE

        // CRITICAL: Child must use parent's page table, not kernel's!
        // The parent is already running with a user page table that has
        // the user program mapped. The child needs the same mappings.
        child.context.satp = parent.context.satp;

        // LIMITATION: Child shares parent's page table for simplicity
        // A full implementation would use copy-on-write or separate page tables
        // Set to 0 to prevent double-free on exit
        child.page_table_ppn = 0;
    } else {
        return -1; // No user frame
    }

    // Make child runnable
    scheduler.makeRunnable(child);

    // Parent returns child PID
    const child_pid = @as(isize, @intCast(child.pid));
    return child_pid;
}

// Execute program (replace current process image) - noreturn on success
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

// Entry point for forked child processes - return directly to user mode
pub fn forkedChildReturn() noreturn {
    const child_proc = scheduler.getCurrentProcess() orelse {
        uart.puts("[forkedChildReturn] ERROR: No current process!\n");
        while (true) {
            csr.wfi();
        }
    };

    // Get the child's trap frame
    const frame = child_proc.user_frame orelse {
        uart.puts("[forkedChildReturn] ERROR: No user frame!\n");
        while (true) {
            csr.wfi();
        }
    };

    child_return_to_user(frame);
}

// Execute shell program (replace process image with shell) - noreturn on success
fn execShell(_: *Process) noreturn {
    // Get the shell program code
    const _user_shell_start = @extern([*]const u8, .{ .name = "_user_shell_start" });
    const _user_shell_end = @extern([*]const u8, .{ .name = "_user_shell_end" });

    const start_addr = @intFromPtr(_user_shell_start);
    const end_addr = @intFromPtr(_user_shell_end);
    const code_size = end_addr - start_addr;

    if (code_size > 0 and code_size < config.Process.MAX_SHELL_SIZE) {
        const code = @as([*]const u8, @ptrFromInt(start_addr))[0..code_size];

        // Execute the shell using the existing user program execution
        // This should never return on success
        user.executeUserProgram(code, "") catch {
            scheduler.exit(-1);
        };

        // If we somehow get here, the exec failed
        scheduler.exit(-1);
    } else {
        scheduler.exit(-1);
    }
    unreachable;
}
