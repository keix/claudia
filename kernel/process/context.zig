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

pub fn processEntryPointWithProc(proc: *Process) noreturn {
    const name = proc.getName();
    if (std.mem.eql(u8, name, "init")) {
        user.initActualUserMode();
        unreachable;
    } else if (std.mem.eql(u8, name, "child")) {
        if (proc.user_frame) |frame| {
            validateKernelPointer(frame);
            returnToUserMode(frame);
        } else {
            scheduler.exit(-1);
        }
    } else if (std.mem.eql(u8, name, "idle")) {
        scheduler.idleLoop();
    } else {
        scheduler.exit(0);
    }
    unreachable;
}

fn initContextCommon(proc: *Process, entry_point: u64) void {
    proc.context.sp = @intFromPtr(proc.stack.ptr) + proc.stack.len - config.Process.STACK_ALIGNMENT;
    proc.context.ra = entry_point;
    proc.context.s0 = @intFromPtr(proc);
    // satp will be set by scheduler based on proc.page_table_ppn
}

pub fn initProcessContext(proc: *Process) void {
    initContextCommon(proc, @intFromPtr(&processEntryPoint));
}

fn processEntryPoint() noreturn {
    const proc: *Process = asm volatile ("mv %[proc], s0"
        : [proc] "=r" (-> *Process),
    );

    processEntryPointWithProc(proc);
}

const SPP_BIT: u6 = 8;
const SPIE_BIT: u6 = 5;

pub fn initIdleContext(proc: *Process) void {
    initContextCommon(proc, @intFromPtr(&scheduler.idleLoop));
    // sstatus will be managed by interrupt enable/disable in scheduler
}

fn validateKernelPointer(ptr: anytype) void {
    if (@intFromPtr(ptr) < config.MemoryLayout.USER_KERNEL_BOUNDARY) {
        while (true) {
            csr.wfi();
        }
    }
}

pub noinline fn returnToUserMode(frame: *trap.TrapFrame) noreturn {
    // Clear GP to prevent kernel GP-relative addressing in user mode
    asm volatile ("li gp, 0");

    // Double-check frame is in kernel space for safety
    validateKernelPointer(frame);

    const cur_sstatus = csr.readSstatus();
    const cleared_spp = cur_sstatus & ~(@as(u64, 1) << SPP_BIT);
    const sstatus_val = cleared_spp | (@as(u64, 1) << SPIE_BIT);

    asm volatile (
        \\csrw sepc, %[pc]
        \\csrw sscratch, %[user_sp]
        \\csrw sstatus, %[sstatus]
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
