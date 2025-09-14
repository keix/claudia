// System call implementations for process management
// Fork, exec, and exit system calls

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

// External assembly function for returning to user mode
const child_return_to_user = @extern(*const fn (*trap.TrapFrame) callconv(.C) noreturn, .{ .name = "child_return_to_user" });

// Fork current process (simplified implementation)
pub fn fork() isize {

    // Reap any zombie processes before allocating new resources
    scheduler.reapZombies();

    // Disable interrupts during critical fork operations to prevent race conditions
    const saved_sie = csr.csrrc(csr.CSR.sstatus, csr.SSTATUS.SIE);
    defer {
        if ((saved_sie & csr.SSTATUS.SIE) != 0) {
            _ = csr.csrrs(csr.CSR.sstatus, csr.SSTATUS.SIE);
        }
    }

    const parent = scheduler.getCurrentProcess() orelse {
        return defs.ESRCH;
    };

    // Allocate static kernel stack for child (simple allocator)
    const child_stack = scheduler.allocateChildStack() orelse {
        return defs.ENOMEM;
    };

    // Create child process
    const child = scheduler.allocProcess("child", child_stack) orelse {
        return defs.EAGAIN;
    };

    // Copy parent process context - but child should not go to processEntryPoint
    // Instead, child should resume from the syscall return point
    child.parent = parent;

    // Create independent page table for child
    var child_pt = virtual.PageTable{ .root_ppn = 0 };
    child_pt.init() catch {
        return defs.ENOMEM;
    };

    // Copy kernel mappings to child page table
    virtual.buildKernelGlobalMappings(&child_pt) catch {
        child_pt.deinit();
        return defs.ENOMEM;
    };

    // Get parent's page table
    var parent_pt = virtual.PageTable{ .root_ppn = parent.page_table_ppn };

    if (parent_pt.root_ppn == 0) {
        // Parent is using kernel page table, get it from satp
        const satp = csr.readSatp();
        parent_pt.root_ppn = (satp >> 44) & 0xFFFFFFFFF;
    }

    // Clone user space from parent to child
    virtual.cloneUserSpace(&parent_pt, &child_pt) catch {
        child_pt.deinit();
        return defs.ENOMEM;
    };

    // Map child's kernel stack to its page table
    // Child process has its own kernel stack allocated by allocateChildStack()
    const child_stack_start = @intFromPtr(child.stack.ptr);
    const child_stack_pages = (child.stack.len + page_size - 1) / page_size;

    // Map each page of the child's kernel stack
    for (0..child_stack_pages) |i| {
        const vaddr = child_stack_start + i * page_size;
        const paddr = vaddr; // Kernel addresses are identity mapped

        child_pt.map(vaddr, paddr, virtual.PTE_R | virtual.PTE_W | virtual.PTE_G) catch {
            child_pt.deinit();
            return defs.ENOMEM;
        };
    }

    // Set child's page table
    child.page_table_ppn = child_pt.root_ppn;

    // Copy heap management info from parent
    child.heap_start = parent.heap_start;
    child.heap_end = parent.heap_end;

    // Copy user mode trap frame if it exists
    if (parent.user_frame) |parent_frame| {
        // Allocate independent trap frame for child
        const child_frame = scheduler.allocateChildTrapFrame() orelse {
            child_pt.deinit();
            return defs.ENOMEM;
        };
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

        // CRITICAL: Set proper mode in context for return to user mode
        // SPP=0 (user mode), SPIE=1 (interrupts enabled after sret)
        child.context.sstatus = (1 << 5); // SPIE only, SPP=0 for user mode

        // CRITICAL: Child must use its own page table
        // Set satp with the child's page table
        const mode: u64 = 8; // Sv39
        child.context.satp = (mode << 60) | (child.page_table_ppn & 0xFFFFFFFFF);
    } else {
        child_pt.deinit();
        return defs.EINVAL; // No user frame
    }

    // Ensure all memory writes are visible before making child runnable
    // Use RISC-V fence instruction for full memory barrier
    asm volatile ("fence rw, rw" ::: "memory");

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
        while (true) {
            csr.wfi();
        }
    };

    // Get the child's trap frame
    const frame = child_proc.user_frame orelse {
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

// Wait for child process to exit
pub fn sys_wait4(pid: i32, status: ?*i32, options: i32, rusage: ?*anyopaque) isize {
    _ = pid; // Initially only support -1 (any child)
    _ = status; // Initially ignore exit status
    _ = options; // Initially ignore options
    _ = rusage; // Initially ignore usage stats

    const proc = scheduler.getCurrentProcess() orelse {
        return -defs.ESRCH;
    };

    while (true) {
        // Look for zombie children
        for (&scheduler.process_table) |*p| {
            if (p.state == .ZOMBIE and p.parent == proc) {
                // Found one!
                const child_pid = @as(isize, @intCast(p.pid));

                // Clean up the zombie
                p.state = .UNUSED;
                p.parent = null;

                return child_pid;
            }
        }

        // Do we have any children at all?
        var has_child = false;
        for (&scheduler.process_table) |*p| {
            if (p.parent == proc and p.state != .UNUSED) {
                has_child = true;
                break;
            }
        }
        if (!has_child) return -defs.ECHILD;

        // Wait for a child to exit
        proc.state = .SLEEPING;
        scheduler.yield();
    }
}
