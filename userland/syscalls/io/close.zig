// userland/syscalls/io/close.zig - Close file descriptor syscall wrapper
const syscall = @import("syscall");
const abi = @import("abi");

pub fn close(fd: usize) isize {
    return syscall.syscall1(abi.sysno.sys_close, fd);
}
