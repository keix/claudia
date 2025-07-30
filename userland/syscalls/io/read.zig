const syscall = @import("../syscall.zig");

pub const SYS_read: usize = 0;

/// Reads data from a file descriptor into a buffer using the raw `read` syscall.
///
/// - `fd`: file descriptor to read from
/// - `buf`: pointer to the buffer where the data will be stored
/// - `len`: maximum number of bytes to read
///
/// Returns: the number of bytes read on success, or a negative error code on failure.
pub fn read(fd: usize, buf: [*]u8, len: usize) isize {
    return syscall.syscall3(SYS_read, fd, @intFromPtr(buf), len);
}
