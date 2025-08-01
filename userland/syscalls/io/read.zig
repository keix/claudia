const syscall = @import("../syscall.zig");
const sysno = @import("../../sysno.zig");

/// Reads data from a file descriptor into a buffer using the raw `read` syscall.
///
/// - `fd`: file descriptor to read from
/// - `buf`: pointer to the buffer where the data will be stored
/// - `len`: maximum number of bytes to read
///
/// Returns: the number of bytes read on success, or a negative error code on failure.
pub fn read(fd: usize, buf: [*]u8, len: usize) isize {
    return syscall.syscall3(sysno.sys_read, fd, @intFromPtr(buf), len);
}
