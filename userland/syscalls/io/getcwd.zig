// getcwd - Get current working directory
const syscall = @import("syscall");
const abi = @import("abi");

pub fn getcwd(buf: []u8) ![]u8 {
    const result = syscall.syscall2(abi.sysno.sys_getcwd, @intFromPtr(buf.ptr), buf.len);

    if (result < 0) {
        return error.SystemCallFailed;
    }

    return buf[0..@as(usize, @intCast(result))];
}
