// kernel/syscalls/stat.zig - File status system calls
const std = @import("std");
const defs = @import("abi");
const proc = @import("../process/core.zig");
const copy = @import("../user/copy.zig");
const file = @import("../file/core.zig");
const vfs = @import("../fs/vfs.zig");
const csr = @import("../arch/riscv/csr.zig");
const config = @import("../config.zig");

// Simple time counter - seconds since boot (same as in time.zig)
var boot_time: i64 = 1700000000; // Arbitrary epoch time
var boot_cycles: u64 = 0;

// Get current time in seconds since epoch
fn getCurrentTime() i64 {
    // Initialize boot_cycles on first call
    if (boot_cycles == 0) {
        boot_cycles = csr.readTime();
    }

    // Read current timer value
    const current_cycles = csr.readTime();
    const elapsed_cycles = current_cycles - boot_cycles;

    // Convert cycles to seconds
    const elapsed_seconds = @divTrunc(elapsed_cycles, config.Timer.FREQUENCY_HZ);
    return boot_time + @as(i64, @intCast(elapsed_seconds));
}

// Convert internal file type to stat mode bits
fn fileTypeToMode(file_type: file.FileType) u32 {
    return switch (file_type) {
        .REGULAR => defs.S_IFREG,
        .DIRECTORY => defs.S_IFDIR,
        .DEVICE => defs.S_IFCHR,
        .PIPE => defs.S_IFIFO,
        else => defs.S_IFREG,
    };
}

// sys_fstat implementation - get file status by file descriptor
pub fn sys_fstat(fd: usize, stat_addr: usize) isize {
    // Get file from file table
    const file_ptr = file.FileTable.getFile(@intCast(fd)) orelse return defs.EBADF;

    // Build stat structure
    var st: defs.Stat = std.mem.zeroes(defs.Stat);

    // Fill in basic information
    st.st_dev = 0; // We don't have real device numbers yet
    st.st_ino = 0; // We don't track inodes yet
    st.st_nlink = 1; // Hard link count
    st.st_uid = 0; // Root user for now
    st.st_gid = 0; // Root group for now
    st.st_rdev = 0; // Not a device file
    st.st_blksize = 512; // Our block size

    // Set file type and permissions
    const file_type_bits = fileTypeToMode(file_ptr.type);
    const permissions: u32 = switch (file_ptr.type) {
        .DIRECTORY => 0o755,
        .REGULAR => 0o644,
        .DEVICE => 0o666,
        .PIPE => 0o644,
        else => 0o644,
    };
    st.st_mode = file_type_bits | (permissions & 0o777);

    // Set size based on file type and inode
    if (file_ptr.inode) |inode| {
        st.st_size = @intCast(inode.size);
        st.st_blocks = @intCast((inode.size + 511) / 512);
    } else {
        // Device files without inodes
        st.st_size = 0;
        st.st_blocks = 0;
    }

    // Use current time for all timestamps
    const now = getCurrentTime();
    st.st_atime = now;
    st.st_mtime = now;
    st.st_ctime = now;
    st.st_atime_nsec = 0;
    st.st_mtime_nsec = 0;
    st.st_ctime_nsec = 0;

    // Copy stat structure to user space
    _ = copy.copyout(stat_addr, std.mem.asBytes(&st)) catch return defs.EFAULT;

    return 0;
}

// AT_FDCWD constant for fstatat
const AT_FDCWD: isize = -100;

// sys_fstatat implementation - get file status by path
pub fn sys_fstatat(dirfd: usize, pathname: usize, stat_addr: usize, flags: usize) isize {
    _ = flags; // Ignore flags for now (AT_SYMLINK_NOFOLLOW, etc.)

    // For now, only support AT_FDCWD (ignore dirfd)
    const fd = @as(isize, @bitCast(dirfd));
    if (fd != AT_FDCWD) {
        // TODO: Support relative paths from directory fd
        return defs.ENOSYS;
    }

    // Copy pathname from user space
    var path_buf: [256]u8 = undefined;
    const path_len = copy.copyinstr(&path_buf, pathname) catch return defs.EFAULT;
    const path = path_buf[0..path_len];

    // Build absolute path if needed
    var abs_path_buf: [256]u8 = undefined;
    var abs_path: []const u8 = undefined;

    if (path.len > 0 and path[0] == '/') {
        // Already absolute
        abs_path = path;
    } else {
        // Relative path - prepend current directory
        const process = proc.Scheduler.getCurrentProcess() orelse return defs.ESRCH;
        const cwd_len = process.cwd_len;

        // Check buffer size
        if (cwd_len + 1 + path.len >= abs_path_buf.len) {
            return defs.ENAMETOOLONG;
        }

        // Build absolute path
        @memcpy(abs_path_buf[0..cwd_len], process.cwd[0..cwd_len]);
        var pos = cwd_len;

        // Add separator if needed
        if (cwd_len > 1 and process.cwd[cwd_len - 1] != '/') {
            abs_path_buf[pos] = '/';
            pos += 1;
        }

        // Add relative path
        @memcpy(abs_path_buf[pos .. pos + path.len], path);
        pos += path.len;

        abs_path = abs_path_buf[0..pos];
    }

    // Use VFS to resolve the path
    const vnode = vfs.resolvePath(abs_path) orelse return defs.ENOENT;

    // Build stat structure
    var st: defs.Stat = std.mem.zeroes(defs.Stat);

    // Fill in basic information
    st.st_dev = 0; // We don't have real device numbers yet
    st.st_ino = 0; // We don't track inodes in VFS yet
    st.st_nlink = 1; // Hard link count
    st.st_uid = 0; // Root user for now
    st.st_gid = 0; // Root group for now
    st.st_rdev = 0; // Not a device file for now
    st.st_blksize = 512; // Our block size

    // Set file type and permissions based on VNode type
    const file_type_bits = switch (vnode.node_type) {
        .FILE => defs.S_IFREG,
        .DIRECTORY => defs.S_IFDIR,
        .DEVICE => defs.S_IFCHR,
    };

    const permissions: u32 = switch (vnode.node_type) {
        .DIRECTORY => 0o755,
        .FILE => 0o644,
        .DEVICE => 0o666,
    };

    st.st_mode = file_type_bits | (permissions & 0o777);

    // Set size based on node type
    switch (vnode.node_type) {
        .FILE => {
            st.st_size = @intCast(vnode.data_size);
            st.st_blocks = @intCast((vnode.data_size + 511) / 512);
        },
        .DIRECTORY, .DEVICE => {
            st.st_size = 0;
            st.st_blocks = 0;
        },
    }

    // Use current time for all timestamps
    const now = getCurrentTime();
    st.st_atime = now;
    st.st_mtime = now;
    st.st_ctime = now;
    st.st_atime_nsec = 0;
    st.st_mtime_nsec = 0;
    st.st_ctime_nsec = 0;

    // Copy stat structure to user space
    _ = copy.copyout(stat_addr, std.mem.asBytes(&st)) catch return defs.EFAULT;

    return 0;
}
