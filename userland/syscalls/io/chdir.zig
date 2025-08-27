// chdir - Change current working directory
const syscall = @import("syscall");
const abi = @import("abi");

pub fn chdir(path: []const u8) !void {
    // Create null-terminated path
    var path_buf: [256]u8 = undefined;
    if (path.len >= path_buf.len) {
        return error.NameTooLong;
    }
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;

    const result = syscall.syscall1(abi.sysno.sys_chdir, @intFromPtr(&path_buf));

    if (result < 0) {
        return error.SystemCallFailed;
    }
}
