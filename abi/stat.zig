// stat.zig - File status structure for RISC-V 64-bit Linux ABI
// Reference: Linux kernel include/uapi/asm-generic/stat.h

// The stat structure as expected by the Linux ABI
pub const Stat = extern struct {
    st_dev: u64, // Device ID of device containing file
    st_ino: u64, // File serial number (inode number)
    st_mode: u32, // Mode of file (permissions and file type)
    st_nlink: u32, // Number of hard links
    st_uid: u32, // User ID of file
    st_gid: u32, // Group ID of file
    st_rdev: u64, // Device ID (if file is character or block special)
    __pad1: u64, // Padding
    st_size: i64, // For regular files, the file size in bytes
    st_blksize: i32, // Optimal I/O block size for this file
    __pad2: i32, // Padding
    st_blocks: i64, // Number of 512-byte blocks allocated
    st_atime: i64, // Time of last access
    st_atime_nsec: i64, // Nanoseconds part of last access time
    st_mtime: i64, // Time of last modification
    st_mtime_nsec: i64, // Nanoseconds part of last modification time
    st_ctime: i64, // Time of last status change
    st_ctime_nsec: i64, // Nanoseconds part of last status change time
    __unused: [2]i32, // Reserved for future use
};

// File type bits in st_mode
pub const S_IFMT: u32 = 0o170000; // File type mask
pub const S_IFSOCK: u32 = 0o140000; // Socket
pub const S_IFLNK: u32 = 0o120000; // Symbolic link
pub const S_IFREG: u32 = 0o100000; // Regular file
pub const S_IFBLK: u32 = 0o060000; // Block device
pub const S_IFDIR: u32 = 0o040000; // Directory
pub const S_IFCHR: u32 = 0o020000; // Character device
pub const S_IFIFO: u32 = 0o010000; // FIFO (named pipe)

// Macros for checking file type
pub inline fn S_ISREG(m: u32) bool {
    return (m & S_IFMT) == S_IFREG;
}

pub inline fn S_ISDIR(m: u32) bool {
    return (m & S_IFMT) == S_IFDIR;
}

pub inline fn S_ISCHR(m: u32) bool {
    return (m & S_IFMT) == S_IFCHR;
}

pub inline fn S_ISBLK(m: u32) bool {
    return (m & S_IFMT) == S_IFBLK;
}

pub inline fn S_ISFIFO(m: u32) bool {
    return (m & S_IFMT) == S_IFIFO;
}

pub inline fn S_ISLNK(m: u32) bool {
    return (m & S_IFMT) == S_IFLNK;
}

pub inline fn S_ISSOCK(m: u32) bool {
    return (m & S_IFMT) == S_IFSOCK;
}
