// userland/syscalls/io/mkdir.zig - Directory creation syscall wrapper
const syscall = @import("syscall");
const abi = @import("abi");

pub fn mkdirat(dirfd: isize, pathname: []const u8, mode: u32) isize {
    return syscall.syscall3(abi.sysno.sys_mkdirat, @bitCast(dirfd), @intFromPtr(pathname.ptr), mode);
}
