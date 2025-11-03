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

// RISC-V register context for kernel-level process switching
// Minimal implementation - only saves callee-saved registers per RISC-V ABI
// Caller-saved registers (t0-t6, a0-a7) are handled by the compiler
// CSRs (satp, sstatus) are managed separately by the scheduler
pub const Context = struct {
    // Callee-saved registers that must be preserved across function calls
    ra: u64, // x1  - Return address
    sp: u64, // x2  - Stack pointer
    s0: u64, // x8  - Saved register / frame pointer
    s1: u64, // x9  - Saved register
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

    pub fn zero() Context {
        return std.mem.zeroes(Context);
    }
};

// Process control block - optimized for cache alignment
pub const Process = struct {
    // Hot data - frequently accessed together (first cache line)
    state: ProcessState, // Process state (4 bytes)
    pid: PID, // Process ID (4 bytes)
    context: Context, // CPU context for kernel-level switching (112 bytes)

    // Scheduling related (second cache line)
    next: ?*Process, // Simple linked list for process queue (8 bytes)
    parent: ?*Process, // Parent process (8 bytes)
    user_frame: ?*trap.TrapFrame, // User mode trap frame (8 bytes)

    // Memory management (third cache line)
    page_table_ppn: u64, // Physical page number of page table root (8 bytes)
    heap_start: u64, // Start of heap (8 bytes)
    heap_end: u64, // Current end of heap (8 bytes)
    stack: []u8, // Process stack (16 bytes)

    // Cold data - rarely accessed
    exit_code: i32, // Exit code when zombie (4 bytes)
    is_kernel: bool, // Kernel-only process flag (1 byte)
    cwd_len: usize, // Length of current working directory (8 bytes)
    name: [config.Process.NAME_LENGTH]u8, // Process name (16 bytes)
    cwd: [config.Process.CWD_LENGTH]u8, // Current working directory (256 bytes)

    pub fn init(pid: PID, name: []const u8, stack: []u8) Process {
        var proc = Process{
            // Hot data
            .state = .EMBRYO,
            .pid = pid,
            .context = Context.zero(),
            // Scheduling related
            .next = null,
            .parent = null,
            .user_frame = null,
            // Memory management
            .page_table_ppn = 0, // Default to kernel page table
            .heap_start = 0, // Will be initialized when user memory is set up
            .heap_end = 0, // Will be initialized when user memory is set up
            .stack = stack,
            // Cold data
            .exit_code = 0,
            .is_kernel = false,
            .cwd_len = 1,
            .name = std.mem.zeroes([config.Process.NAME_LENGTH]u8),
            .cwd = std.mem.zeroes([config.Process.CWD_LENGTH]u8),
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
