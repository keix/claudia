// getppid - Get parent process ID
const syscall = @import("syscall");
const abi = @import("abi");

pub fn getppid() isize {
    return syscall.syscall0(abi.sysno.sys_getppid);
}
