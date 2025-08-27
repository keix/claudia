// getpid - Get process ID
const syscall = @import("syscall");
const abi = @import("abi");

pub fn getpid() isize {
    return syscall.syscall0(abi.sysno.sys_getpid);
}
