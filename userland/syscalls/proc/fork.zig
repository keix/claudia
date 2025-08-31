// fork system call wrapper
const syscall = @import("syscall");
const abi = @import("abi");

pub fn fork() !isize {
    const result = syscall.syscall1(abi.sysno.sys_fork, 0);
    if (result < 0) {
        return switch (@as(isize, @intCast(-result))) {
            abi.EAGAIN => error.ProcessLimitReached,
            abi.ENOMEM => error.OutOfMemory,
            abi.ENOSYS => error.SystemCallNotImplemented,
            else => error.UnknownError,
        };
    }
    return result;
}