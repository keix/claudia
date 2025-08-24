// kernel/syscalls/dispatch.zig - Full syscall dispatcher
const abi = @import("abi");
const sysno = abi.sysno;
const defs = abi;
const fs = @import("fs.zig");
const process = @import("process.zig");

// Process management function pointer
var proc_exit: ?*const fn (i32) noreturn = null;

// Initialize the dispatcher with required function pointers
pub fn init(
    getFile: *const fn (i32) ?*anyopaque,
    writeFile: *const fn (*anyopaque, []const u8) isize,
    readFile: *const fn (*anyopaque, []u8) isize,
    closeFile: *const fn (i32) isize,
    procExit: *const fn (i32) noreturn,
    procFork: *const fn () isize,
    procExec: *const fn ([]const u8, []const u8) isize,
) void {
    // Initialize fs subsystem
    fs.init(getFile, writeFile, readFile, closeFile);

    // Initialize process subsystem
    process.init(procFork, procExec);

    // Set process exit function
    proc_exit = procExit;
}

pub fn call(n: usize, a0: usize, a1: usize, a2: usize, a3: usize, a4: usize) isize {
    return switch (n) {
        sysno.sys_write => fs.sys_write(a0, a1, a2),
        sysno.sys_read => fs.sys_read(a0, a1, a2),
        sysno.sys_openat => fs.sys_openat(a0, a1, a2, a3),
        sysno.sys_close => fs.sys_close(a0),
        sysno.sys_exit => {
            if (proc_exit) |exit_fn| {
                exit_fn(@as(i32, @intCast(a0)));
                return 0;
            } else {
                return defs.ENOSYS;
            }
        },
        sysno.sys_clone => process.sys_clone(a0, a1, a2, a3, a4),
        sysno.sys_fork => process.sys_fork(),
        sysno.sys_execve => process.sys_execve(a0, a1, a2),
        sysno.sys_sched_yield => process.sys_sched_yield(),
        else => defs.ENOSYS,
    };
}
