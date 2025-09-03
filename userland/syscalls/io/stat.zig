// userland/syscalls/io/stat.zig - File status by path
const syscall = @import("syscall");
const abi = @import("abi");

// Special value for fstatat to use current working directory
pub const AT_FDCWD: isize = -100;

// Flags for fstatat
pub const AT_SYMLINK_NOFOLLOW: u32 = 0x100;
pub const AT_NO_AUTOMOUNT: u32 = 0x800;
pub const AT_EMPTY_PATH: u32 = 0x1000;

// Get file status by path (relative to AT_FDCWD)
pub fn stat(path: *const u8, stat_buf: *abi.Stat) !void {
    const result = syscall.syscall4(abi.sysno.sys_fstatat, @bitCast(@as(isize, AT_FDCWD)), @intFromPtr(path), @intFromPtr(stat_buf), 0 // flags
    );

    if (result < 0) {
        return switch (result) {
            abi.ENOENT => error.FileNotFound,
            abi.ENOTDIR => error.NotDirectory,
            abi.ENAMETOOLONG => error.NameTooLong,
            abi.EFAULT => error.BadAddress,
            abi.EACCES => error.AccessDenied,
            else => error.StatFailed,
        };
    }
}

// Get file status by path with flags
pub fn fstatat(dirfd: i32, path: *const u8, stat_buf: *abi.Stat, flags: u32) !void {
    const result = syscall.syscall4(abi.sysno.sys_fstatat, @as(usize, @intCast(dirfd)), @intFromPtr(path), @intFromPtr(stat_buf), flags);

    if (result < 0) {
        return switch (result) {
            abi.ENOENT => error.FileNotFound,
            abi.ENOTDIR => error.NotDirectory,
            abi.ENAMETOOLONG => error.NameTooLong,
            abi.EFAULT => error.BadAddress,
            abi.EACCES => error.AccessDenied,
            abi.ENOSYS => error.NotSupported,
            else => error.StatFailed,
        };
    }
}
