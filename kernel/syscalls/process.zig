// kernel/syscalls/process.zig - Process management syscalls
const std = @import("std");
const defs = @import("abi");
const proc = @import("../process/core.zig");

// Process management function pointers
var proc_fork: ?*const fn () isize = null;
var proc_exec: ?*const fn ([]const u8, []const u8) isize = null;
var proc_exit: ?*const fn (i32) noreturn = null;

// Initialize process management function pointers
pub fn init(forkFn: *const fn () isize, execFn: *const fn ([]const u8, []const u8) isize, exitFn: *const fn (i32) noreturn) void {
    proc_fork = forkFn;
    proc_exec = execFn;
    proc_exit = exitFn;
}

// sys_clone implementation (simplified fork for now)
pub fn sys_clone(flags: usize, stack: usize, parent_tid: usize, child_tid: usize, tls: usize) isize {
    _ = flags;
    _ = stack;
    _ = parent_tid;
    _ = child_tid;
    _ = tls;

    const forkFn = proc_fork orelse return defs.ENOSYS;
    return forkFn();
}

// Wrapper for traditional fork() behavior
pub fn sys_fork() isize {
    const forkFn = proc_fork orelse {
        return defs.ENOSYS;
    };
    const result = forkFn();
    return result;
}

// sys_execve implementation
pub fn sys_execve(filename_ptr: usize, argv_ptr: usize, envp_ptr: usize) isize {
    _ = argv_ptr;
    _ = envp_ptr;
    _ = filename_ptr;

    const execFn = proc_exec orelse return defs.ENOSYS;

    // For simplicity, hardcode shell execution for now
    // This avoids the user space memory access issue
    return execFn("shell", "");
}

// sys_sched_yield implementation
pub fn sys_sched_yield() isize {
    // Yield current process to scheduler
    const proc_yield = proc.Scheduler.yield;
    proc_yield();
    return 0; // Always succeeds
}

// sys_getpid implementation
pub fn sys_getpid() isize {
    const current = proc.Scheduler.getCurrentProcess() orelse return defs.ESRCH;
    return @intCast(current.pid);
}

// sys_getppid implementation
pub fn sys_getppid() isize {
    const current = proc.Scheduler.getCurrentProcess() orelse return defs.ESRCH;
    if (current.parent) |parent| {
        return @intCast(parent.pid);
    }
    return 1; // Parent is init process
}

// sys_exit implementation
pub fn sys_exit(status: usize) isize {
    const exitFn = proc_exit orelse return defs.ENOSYS;
    exitFn(@as(i32, @intCast(status)));
    return 0; // Never reached
}

// sys_wait4 implementation
pub fn sys_wait4(pid: usize, status: usize, options: usize, rusage: usize) isize {
    // Handle -1 as usize (truncate to i32)
    const pid_i32: i32 = @as(i32, @truncate(@as(i64, @bitCast(pid))));
    const status_ptr = if (status != 0) @as(?*i32, @ptrFromInt(status)) else null;
    const options_i32 = @as(i32, @intCast(options));
    const rusage_ptr = if (rusage != 0) @as(?*anyopaque, @ptrFromInt(rusage)) else null;

    return proc.syscalls.sys_wait4(pid_i32, status_ptr, options_i32, rusage_ptr);
}
