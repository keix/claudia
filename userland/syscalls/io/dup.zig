// userland/syscalls/io/dup.zig - Duplicate file descriptor
const syscall = @import("syscall");
const abi = @import("abi");

// Duplicate file descriptor to lowest available
pub fn dup(oldfd: i32) !i32 {
    const result = syscall.syscall1(abi.sysno.sys_dup, @as(usize, @intCast(oldfd)));

    if (result < 0) {
        return switch (result) {
            abi.EBADF => error.BadFileDescriptor,
            abi.EMFILE => error.TooManyOpenFiles,
            else => error.DupFailed,
        };
    }

    return @intCast(result);
}

// Duplicate file descriptor to specific fd
pub fn dup2(oldfd: i32, newfd: i32) !i32 {
    // Linux uses dup3 with flags=0 for dup2 functionality
    const result = syscall.syscall3(abi.sysno.sys_dup3, @as(usize, @intCast(oldfd)), @as(usize, @intCast(newfd)), 0 // flags
    );

    if (result < 0) {
        return switch (result) {
            abi.EBADF => error.BadFileDescriptor,
            abi.EINVAL => error.InvalidArgument,
            abi.EMFILE => error.TooManyOpenFiles,
            else => error.Dup2Failed,
        };
    }

    return @intCast(result);
}
