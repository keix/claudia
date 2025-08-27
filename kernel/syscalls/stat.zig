// kernel/syscalls/stat.zig - File status system calls
const std = @import("std");
const defs = @import("abi");
const proc = @import("../process/core.zig");
const copy = @import("../user/copy.zig");
const file = @import("../file/core.zig");

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
    st.st_ino = if (file_ptr.inode) |inode| inode.inum else 0;
    st.st_nlink = 1; // Hard link count
    st.st_uid = 0; // Root user for now
    st.st_gid = 0; // Root group for now
    st.st_rdev = 0; // Not a device file
    st.st_blksize = 512; // Our block size

    // Set file type and permissions
    const file_type_bits = fileTypeToMode(file_ptr.type);
    const permissions = if (file_ptr.inode) |inode| inode.mode else 0o644;
    st.st_mode = file_type_bits | (permissions & 0o777);

    // Set size and block count
    if (file_ptr.inode) |inode| {
        st.st_size = @intCast(inode.size);
        st.st_blocks = @intCast((inode.size + 511) / 512); // Number of 512-byte blocks

        // Set timestamps
        st.st_atime = inode.atime;
        st.st_atime_nsec = 0;
        st.st_mtime = inode.mtime;
        st.st_mtime_nsec = 0;
        st.st_ctime = inode.ctime;
        st.st_ctime_nsec = 0;
    } else {
        // For device files without inodes
        st.st_size = 0;
        st.st_blocks = 0;
        st.st_atime = 0;
        st.st_mtime = 0;
        st.st_ctime = 0;
    }

    // Copy stat structure to user space
    _ = copy.copyout(stat_addr, std.mem.asBytes(&st)) catch return defs.EFAULT;

    return 0;
}
