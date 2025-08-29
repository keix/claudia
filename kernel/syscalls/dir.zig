// kernel/syscalls/dir.zig - Directory operations
const std = @import("std");
const defs = @import("abi");
const copy = @import("../user/copy.zig");
const vfs = @import("../fs/vfs.zig");
const simplefs = @import("../fs/simplefs.zig");
const process = @import("../process/core.zig");
const fs = @import("fs.zig");
const uart = @import("../driver/uart/core.zig");

// Directory entry structure for getdents64
pub const DirEntry = extern struct {
    d_ino: u64, // Inode number
    d_off: i64, // Offset to next dirent
    d_reclen: u16, // Length of this record
    d_type: u8, // File type
    d_name: [256]u8, // Filename (null-terminated)
};

// AT_FDCWD constant for *at syscalls
const AT_FDCWD: isize = -100;

// Create a directory
pub fn sys_mkdirat(dirfd: usize, pathname: usize, mode: usize) isize {
    _ = mode; // Ignore mode for now

    // For now, only support AT_FDCWD (current directory)
    const fd = @as(isize, @bitCast(dirfd));
    if (fd != AT_FDCWD) {
        return defs.ENOSYS; // Not implemented for directory fds
    }

    // Get current process
    const current = process.Scheduler.getCurrentProcess() orelse return defs.ESRCH;

    // Copy pathname from user space
    var path_buf: [256]u8 = undefined;
    const path_len = copy.copyinstr(&path_buf, pathname) catch return defs.EFAULT;
    const path = path_buf[0..path_len];

    // Parse the path to get parent directory and new directory name
    var parent_path: []const u8 = "/";
    var dir_name: []const u8 = path;

    // Find the last slash to separate parent path and directory name
    if (std.mem.lastIndexOf(u8, path, "/")) |last_slash| {
        if (last_slash == 0) {
            // Creating directory in root
            parent_path = "/";
            dir_name = path[1..];
        } else {
            parent_path = path[0..last_slash];
            dir_name = path[last_slash + 1 ..];
        }
    } else {
        // No slash, create in current directory
        parent_path = current.cwd[0..current.cwd_len];
    }

    // Don't allow empty directory names
    if (dir_name.len == 0) {
        return defs.EINVAL;
    }

    // Create the directory in VFS
    if (vfs.createDirectory(parent_path, dir_name) == null) {
        // Could be because parent doesn't exist, directory already exists, etc.
        return defs.EEXIST;
    }

    // Also create in SimpleFS if it's mounted
    // For now, we'll skip persistence to disk
    // TODO: Integrate with SimpleFS for persistent storage

    return 0;
}

pub fn sys_getdents64(fd: usize, dirp: usize, count: usize) isize {
    // Get the file handle
    const file_table = @import("../file/core.zig").FileTable;
    const file = file_table.getFile(@intCast(fd)) orelse return defs.EBADF;

    // Read directory entries
    var buffer: [4096]u8 = undefined;
    const max_read = if (count > buffer.len) buffer.len else count;
    const result = file.read(buffer[0..max_read]);
    if (result < 0) return result;

    const bytes_read = @as(usize, @intCast(result));

    // Copy to user space
    _ = copy.copyout(dirp, buffer[0..bytes_read]) catch return defs.EFAULT;

    return @intCast(bytes_read);
}
