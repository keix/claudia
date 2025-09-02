// fork system call wrapper
const syscall = @import("syscall");
const abi = @import("abi");

pub fn fork() !isize {
    const result = syscall.syscall0(abi.sysno.sys_fork);
    if (result < 0) {
        return switch (result) {
            abi.EAGAIN => error.ProcessLimitReached,
            abi.ENOMEM => error.OutOfMemory,
            abi.ENOSYS => error.SystemCallNotImplemented,
            abi.ESRCH => error.NoSuchProcess,
            abi.EINVAL => error.InvalidArgument,
            else => error.UnknownError,
        };
    }
    return result;
}
