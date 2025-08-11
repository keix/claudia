// kernel/syscalls/dispatch.zig - Full syscall dispatcher
const sysno = @import("sysno");
const defs = @import("abi");
const fs = @import("fs.zig");

// Process management function pointer
var proc_exit: ?*const fn (i32) noreturn = null;

// Initialize the dispatcher with required function pointers
pub fn init(
    getFile: *const fn (i32) ?*anyopaque,
    writeFile: *const fn (*anyopaque, []const u8) isize,
    readFile: *const fn (*anyopaque, []u8) isize,
    closeFile: *const fn (i32) isize,
    procExit: *const fn (i32) noreturn,
) void {
    // Initialize fs subsystem
    fs.init(getFile, writeFile, readFile, closeFile);

    // Set process exit function
    proc_exit = procExit;
}

pub fn call(n: usize, a0: usize, a1: usize, a2: usize) isize {
    return switch (n) {
        sysno.sys_write => fs.sys_write(a0, a1, a2),
        sysno.sys_read => fs.sys_read(a0, a1, a2),
        sysno.sys_close => fs.sys_close(a0),
        sysno.sys_exit => {
            if (proc_exit) |exit_fn| {
                exit_fn(@as(i32, @intCast(a0)));
                return 0;
            } else {
                return defs.ENOSYS;
            }
        },
        else => defs.ENOSYS,
    };
}
