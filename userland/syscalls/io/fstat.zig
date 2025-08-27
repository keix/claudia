// fstat - Get file status by file descriptor
const syscall = @import("syscall");
const abi = @import("abi");

pub fn fstat(fd: i32, stat: *abi.Stat) !void {
    const result = syscall.syscall2(abi.sysno.sys_fstat, @intCast(fd), @intFromPtr(stat));

    if (result < 0) {
        return error.SystemCallFailed;
    }
}
