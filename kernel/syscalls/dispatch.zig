// kernel/syscalls/dispatch.zig - Full syscall dispatcher
const abi = @import("abi");
const sysno = abi.sysno;
const defs = abi;
const fs = @import("fs.zig");
const process = @import("process.zig");
const dir = @import("dir.zig");
const io = @import("io.zig");
const path = @import("path.zig");
const stat = @import("stat.zig");
const time = @import("time.zig");
const uid = @import("uid.zig");
const brk = @import("brk.zig");

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
    process.init(procFork, procExec, procExit);
}

pub fn call(n: usize, a0: usize, a1: usize, a2: usize, a3: usize, a4: usize) isize {
    return switch (n) {
        sysno.sys_write => fs.sys_write(a0, a1, a2),
        sysno.sys_read => fs.sys_read(a0, a1, a2),
        sysno.sys_openat => fs.sys_openat(a0, a1, a2, a3),
        sysno.sys_close => fs.sys_close(a0),
        sysno.sys_lseek => io.sys_lseek(a0, a1, a2),
        sysno.sys_dup => io.sys_dup(a0),
        sysno.sys_dup3 => io.sys_dup3(a0, a1, a2),
        sysno.sys_getdents64 => dir.sys_getdents64(a0, a1, a2),
        sysno.sys_exit => process.sys_exit(a0),
        sysno.sys_clone => process.sys_clone(a0, a1, a2, a3, a4),
        sysno.sys_fork => process.sys_fork(),
        sysno.sys_execve => process.sys_execve(a0, a1, a2),
        sysno.sys_sched_yield => process.sys_sched_yield(),
        sysno.sys_getpid => process.sys_getpid(),
        sysno.sys_getppid => process.sys_getppid(),
        sysno.sys_getcwd => path.sys_getcwd(a0, a1),
        sysno.sys_chdir => path.sys_chdir(a0),
        sysno.sys_fstat => stat.sys_fstat(a0, a1),
        sysno.sys_fstatat => stat.sys_fstatat(a0, a1, a2, a3),
        sysno.sys_time => time.sys_time(a0),
        sysno.sys_clock_gettime => time.sys_clock_gettime(a0, a1),
        sysno.sys_nanosleep => time.sys_nanosleep(a0, a1),
        sysno.sys_getuid => uid.sys_getuid(),
        sysno.sys_geteuid => uid.sys_geteuid(),
        sysno.sys_getgid => uid.sys_getgid(),
        sysno.sys_getegid => uid.sys_getegid(),
        sysno.sys_setuid => uid.sys_setuid(a0),
        sysno.sys_setgid => uid.sys_setgid(a0),
        sysno.sys_mkdirat => dir.sys_mkdirat(a0, a1, a2),
        sysno.sys_unlinkat => dir.sys_unlinkat(a0, a1, a2),
        sysno.sys_wait4 => process.sys_wait4(a0, a1, a2, a3),
        sysno.sys_brk => brk.sys_brk(a0),
        999 => blk: { // Debug syscall to get timer interrupt count
            const counter = @import("../time/counter.zig");
            break :blk @as(isize, @intCast(counter.get()));
        },
        else => defs.ENOSYS,
    };
}
