const syscall = @import("syscall");
const abi = @import("abi");

// Simple wait for any child process
pub fn wait() !i32 {
    const result = syscall.syscall4(abi.sysno.sys_wait4, @as(usize, @bitCast(@as(u64, @bitCast(@as(i64, -1))))), // Wait for any child
        0, // No status
        0, // No options
        0 // No rusage
    );

    if (result >= 0) {
        return @intCast(result);
    }

    return switch (result) {
        abi.ECHILD => error.NoChildren,
        abi.ESRCH => error.NoSuchProcess,
        else => error.WaitFailed,
    };
}
