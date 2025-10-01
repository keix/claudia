const std = @import("std");
const trap = @import("../trap/core.zig");
const config = @import("../config.zig");

pub const PID = u32;

// Process states in the lifecycle
pub const ProcessState = enum {
    UNUSED, // Process slot is free
    EMBRYO, // Process is being created
    SLEEPING, // Process is blocked waiting for event
    RUNNABLE, // Process is ready to run
    RUNNING, // Process is currently executing
    ZOMBIE, // Process has exited but not yet cleaned up
};

pub const WaitQ = struct {
    head: ?*Process = null,

    pub fn init() WaitQ {
        return WaitQ{ .head = null };
    }
};

// RISC-V register context for kernel-level process switching
// Saved/restored by context_switch assembly routine
pub const Context = struct {
    // Callee-saved registers (preserved across function calls)
    ra: u64, // x1  - Return address
    sp: u64, // x2  - Stack pointer
    gp: u64, // x3  - Global pointer (not used in kernel)
    tp: u64, // x4  - Thread pointer (per-CPU data)

    // Caller-saved registers (temporary)
    t0: u64, // x5  - Temporary/alternate return address
    t1: u64, // x6  - Temporary
    t2: u64, // x7  - Temporary

    // Callee-saved registers
    s0: u64, // x8  - Frame pointer / saved register
    s1: u64, // x9  - Saved register

    // Function arguments and return values
    a0: u64, // x10 - Function arg 0 / return value 0
    a1: u64, // x11 - Function arg 1 / return value 1
    a2: u64, // x12 - Function arg 2
    a3: u64, // x13 - Function arg 3
    a4: u64, // x14 - Function arg 4
    a5: u64, // x15 - Function arg 5
    a6: u64, // x16 - Function arg 6
    a7: u64, // x17 - Function arg 7

    // More callee-saved registers
    s2: u64, // x18 - Saved register
    s3: u64, // x19 - Saved register
    s4: u64, // x20 - Saved register
    s5: u64, // x21 - Saved register
    s6: u64, // x22 - Saved register
    s7: u64, // x23 - Saved register
    s8: u64, // x24 - Saved register
    s9: u64, // x25 - Saved register
    s10: u64, // x26 - Saved register
    s11: u64, // x27 - Saved register

    // More caller-saved registers
    t3: u64, // x28 - Temporary
    t4: u64, // x29 - Temporary
    t5: u64, // x30 - Temporary
    t6: u64, // x31 - Temporary

    // Supervisor CSRs
    satp: u64, // Supervisor Address Translation and Protection
    sepc: u64, // Supervisor Exception Program Counter
    sstatus: u64, // Supervisor Status Register

    pub fn zero() Context {
        return std.mem.zeroes(Context);
    }
};

// Process Control Block (PCB) - main process data structure
pub const Process = struct {
    pid: PID, // Process identifier
    state: ProcessState, // Current state
    context: Context, // Saved register state
    user_frame: ?*trap.TrapFrame, // User mode registers (null for kernel processes)
    stack: []u8, // Kernel stack
    name: [config.Process.NAME_LENGTH]u8, // Process name
    parent: ?*Process, // Parent process
    exit_code: i32, // Exit status for zombies
    is_kernel: bool, // Kernel-only process flag
    cwd: [config.Process.CWD_LENGTH]u8, // Current working directory
    cwd_len: usize, // CWD string length
    page_table_ppn: u64, // Root page table PPN (0 = use kernel PT)

    // Memory management
    heap_start: u64, // Start of heap (brk)
    heap_end: u64, // Current heap end

    // Scheduler queue link
    next: ?*Process, // Next in ready/wait queue

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
            .page_table_ppn = 0,
            .heap_start = 0,
            .heap_end = 0,
            .next = null,
        };

        // Initialize with root directory
        proc.cwd[0] = '/';
        proc.cwd[1] = 0;

        const copy_len = @min(name.len, config.Process.NAME_LENGTH - 1);
        @memcpy(proc.name[0..copy_len], name[0..copy_len]);
        proc.name[copy_len] = 0;

        return proc;
    }

    pub fn getName(self: *const Process) []const u8 {
        const len = std.mem.indexOfScalar(u8, &self.name, 0) orelse self.name.len;
        return self.name[0..len];
    }
};

// Check if process has terminated (zombie or unused)
pub inline fn isTerminated(proc: *const Process) bool {
    return proc.state == .ZOMBIE or proc.state == .UNUSED;
}
