// Context management and process entry points
// Handles context initialization and switching logic

const std = @import("std");
const csr = @import("../arch/riscv/csr.zig");
const uart = @import("../driver/uart/core.zig");
const trap = @import("../trap/core.zig");
const user = @import("../user/core.zig");
const config = @import("../config.zig");
const memory = @import("../memory/core.zig");

const types = @import("types.zig");
const scheduler = @import("scheduler.zig");
const syscalls = @import("syscalls.zig");

pub const Process = types.Process;
pub const Context = types.Context;

// Entry point for process with direct pointer passing
pub fn processEntryPointWithProc(proc: *Process) noreturn {
    // Run process-specific code based on process name
    const name = proc.getName();
    if (std.mem.eql(u8, name, "init")) {
        user.initActualUserMode();
        unreachable; // Should not return
    } else if (std.mem.eql(u8, name, "child")) {
        // The trap frame should already be set up to return to the correct location
        if (proc.user_frame) |frame| {

            // Verify frame is in kernel space
            validateKernelPointer(frame);

            // Return to user mode by pretending we came from a trap
            // This is a bit of a hack, but it should work for basic fork
            returnToUserMode(frame);
        } else {
            // No trap frame - exit
            scheduler.exit(-1);
        }
    } else if (std.mem.eql(u8, name, "idle")) {
        // Idle process - jump to our own idle loop
        scheduler.idleLoop();
    } else {
        // Generic process - just exit
        scheduler.exit(0);
    }
    unreachable;
}

// Common context initialization logic
fn initContextCommon(proc: *Process, entry_point: u64) void {
    // Set up stack pointer to top of allocated stack (grows downward)
    proc.context.sp = @intFromPtr(proc.stack.ptr) + proc.stack.len - config.Process.STACK_ALIGNMENT;

    // Set return address to specified entry point
    proc.context.ra = entry_point;

    // Callee-saved registers already zeroed by Context.zero()

    // Store process pointer in s0 so entry point can access it
    proc.context.s0 = @intFromPtr(proc);

    // Set SATP to kernel page table
    proc.context.satp = csr.SATP_SV39 | memory.kernel_page_table.root_ppn;
}

// Initialize process context for context switching
pub fn initProcessContext(proc: *Process) void {
    initContextCommon(proc, @intFromPtr(&processEntryPoint));
}

// Entry point for newly created processes (called via context switch)
fn processEntryPoint() noreturn {
    // Get process pointer from s0 register (passed from context init)
    const proc: *Process = asm volatile ("mv %[proc], s0"
        : [proc] "=r" (-> *Process),
    );

    // Delegate to common entry point
    processEntryPointWithProc(proc);
}

// Initialize idle process context
pub fn initIdleContext(proc: *Process) void {
    initContextCommon(proc, @intFromPtr(&scheduler.idleLoop));

    // Set sstatus for supervisor mode (SPP=1)
    proc.context.sstatus = (1 << 8) | (1 << 5); // SPP | SPIE
}

// Validate that a pointer is in kernel space
fn validateKernelPointer(ptr: anytype) void {
    if (@intFromPtr(ptr) < config.MemoryLayout.USER_KERNEL_BOUNDARY) {
        while (true) {
            csr.wfi();
        }
    }
}

// Return to user mode with given trap frame
pub noinline fn returnToUserMode(frame: *trap.TrapFrame) noreturn {
    // CRITICAL: Ensure GP is 0 before accessing anything
    asm volatile ("li gp, 0");

    // Double-check frame pointer is in kernel space
    validateKernelPointer(frame);

    // Set up RISC-V CSRs for return to user mode
    // SSTATUS: Use RMW to only modify SPP=0, SPIE=1, preserve other flags
    const cur_sstatus = csr.readSstatus();
    const cleared_spp = cur_sstatus & ~(@as(u64, 1) << 8); // SPP=0
    const sstatus_val = cleared_spp | (@as(u64, 1) << 5); // SPIE=1

    // Just use the simple assembly version
    asm volatile (
    // Set up CSRs
        \\csrw sepc, %[pc]
        \\csrw sscratch, %[user_sp]
        \\csrw sstatus, %[sstatus]

        // Restore user registers from trap frame
        \\ld ra, 8(%[frame])
        \\ld gp, 16(%[frame])
        \\ld tp, 24(%[frame])
        \\ld t0, 32(%[frame])
        \\ld t1, 40(%[frame])
        \\ld t2, 48(%[frame])
        \\ld s0, 56(%[frame])
        \\ld s1, 64(%[frame])
        \\ld a0, 72(%[frame])
        \\ld a1, 80(%[frame])
        \\ld a2, 88(%[frame])
        \\ld a3, 96(%[frame])
        \\ld a4, 104(%[frame])
        \\ld a5, 112(%[frame])
        \\ld a6, 120(%[frame])
        \\ld a7, 128(%[frame])
        \\ld s2, 136(%[frame])
        \\ld s3, 144(%[frame])
        \\ld s4, 152(%[frame])
        \\ld s5, 160(%[frame])
        \\ld s6, 168(%[frame])
        \\ld s7, 176(%[frame])
        \\ld s8, 184(%[frame])
        \\ld s9, 192(%[frame])
        \\ld s10, 200(%[frame])
        \\ld s11, 208(%[frame])
        \\ld t3, 216(%[frame])
        \\ld t4, 224(%[frame])
        \\ld t5, 232(%[frame])
        \\ld t6, 240(%[frame])

        // Switch to user stack and return
        \\csrrw sp, sscratch, sp
        \\fence.i
        \\sfence.vma zero, zero
        \\sret
        :
        : [frame] "r" (frame),
          [pc] "r" (frame.sepc),
          [user_sp] "r" (frame.sp),
          [sstatus] "r" (sstatus_val),
        : "memory"
    );

    unreachable;
}
