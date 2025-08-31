// Process types and data structures for Claudia kernel
// RISC-V specific process structures

const std = @import("std");
const trap = @import("../trap/core.zig");
const config = @import("../config.zig");

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

// Wait queue for blocking I/O
pub const WaitQ = struct {
    head: ?*Process = null,

    pub fn init() WaitQ {
        return WaitQ{ .head = null };
    }
};

// RISC-V CPU context for process switching (all general purpose registers)
// Matches the layout expected by context.S
pub const Context = struct {
    ra: u64, // x1 - return address
    sp: u64, // x2 - stack pointer
    gp: u64, // x3 - global pointer
    tp: u64, // x4 - thread pointer
    t0: u64, // x5 - temporary
    t1: u64, // x6 - temporary
    t2: u64, // x7 - temporary
    s0: u64, // x8 - saved register / frame pointer
    s1: u64, // x9 - saved register
    a0: u64, // x10 - function argument/return value
    a1: u64, // x11 - function argument
    a2: u64, // x12 - function argument
    a3: u64, // x13 - function argument
    a4: u64, // x14 - function argument
    a5: u64, // x15 - function argument
    a6: u64, // x16 - function argument
    a7: u64, // x17 - function argument
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
    satp: u64, // Supervisor Address Translation and Protection register
    sepc: u64, // Supervisor Exception Program Counter
    sstatus: u64, // Supervisor Status register

    pub fn zero() Context {
        return std.mem.zeroes(Context);
    }
};

// Process control block
pub const Process = struct {
    pid: PID, // Process ID
    state: ProcessState, // Process state
    context: Context, // CPU context for kernel-level switching
    user_frame: ?*trap.TrapFrame, // User mode trap frame (null for kernel processes)
    stack: []u8, // Process stack
    name: [config.Process.NAME_LENGTH]u8, // Process name (null-terminated)
    parent: ?*Process, // Parent process
    exit_code: i32, // Exit code when zombie
    is_kernel: bool, // Kernel-only process flag
    cwd: [config.Process.CWD_LENGTH]u8, // Current working directory
    cwd_len: usize, // Length of current working directory
    page_table_ppn: u64, // Physical page number of page table root (0 = kernel PT)

    // Simple linked list for process queue
    next: ?*Process,

    pub fn init(pid: PID, name: []const u8, stack: []u8) Process {
        var proc = Process{
            .pid = pid,
            .state = .EMBRYO,
            .context = Context.zero(),
            .user_frame = null,
            .stack = stack,
            .name = std.mem.zeroes([config.Process.NAME_LENGTH]u8),
            .parent = null,
            .exit_code = 0,
            .is_kernel = false,
            .cwd = std.mem.zeroes([config.Process.CWD_LENGTH]u8),
            .cwd_len = 1,
            .page_table_ppn = 0, // Default to kernel page table
            .next = null,
        };

        // Initialize with root directory
        proc.cwd[0] = '/';
        proc.cwd[1] = 0;

        // Copy name (max NAME_LENGTH-1 chars + null terminator)
        const copy_len = @min(name.len, config.Process.NAME_LENGTH - 1);
        @memcpy(proc.name[0..copy_len], name[0..copy_len]);
        proc.name[copy_len] = 0;

        // Don't initialize context here - it will be done after assignment to table

        return proc;
    }

    pub fn getName(self: *const Process) []const u8 {
        const len = std.mem.indexOfScalar(u8, &self.name, 0) orelse self.name.len;
        return self.name[0..len];
    }
};

pub inline fn isTerminated(proc: *const Process) bool {
    return proc.state == .ZOMBIE or proc.state == .UNUSED;
}
