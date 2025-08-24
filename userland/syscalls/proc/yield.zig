const syscall = @import("syscall");
const abi = @import("abi");

/// Yields the CPU to other processes using the `sched_yield` syscall.
/// This is useful to prevent busy-waiting and reduce CPU usage.
///
/// Returns: 0 on success, or a negative error code on failure.
pub fn yield() isize {
    return syscall.syscall1(abi.sysno.sys_sched_yield, 0);
}
