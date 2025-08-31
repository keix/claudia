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
    const forkFn = proc_fork orelse return defs.ENOSYS;
    return forkFn();
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

// sys_exit implementation
pub fn sys_exit(status: usize) isize {
    const exitFn = proc_exit orelse return defs.ENOSYS;
    exitFn(@as(i32, @intCast(status)));
    return 0; // Never reached
}
