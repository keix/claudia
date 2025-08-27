// userland/syscalls/io/lseek.zig - lseek system call wrapper
const std = @import("std");
const abi = @import("abi");
const syscall = @import("syscall");

pub fn lseek(fd: i32, offset: i64, whence: i32) !i64 {
    const result = syscall.syscall3(abi.sysno.sys_lseek, @as(usize, @intCast(fd)), @as(usize, @bitCast(offset)), @as(usize, @intCast(whence)));

    if (result < 0) {
        return error.SystemCallFailed;
    }

    return @as(i64, @intCast(result));
}
