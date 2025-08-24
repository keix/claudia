const syscall = @import("syscall");
const abi = @import("abi");

/// Writes the contents of a buffer to a file descriptor using the raw `write` syscall.
///
/// - `fd`: file descriptor to write to
/// - `buf`: pointer to the data to write
/// - `len`: number of bytes to write
///
/// Returns: the number of bytes written on success, or a negative error code on failure.
pub fn write(fd: usize, buf: *const u8, len: usize) isize {
    return syscall.syscall3(abi.sysno.sys_write, fd, @intFromPtr(buf), len);
}
