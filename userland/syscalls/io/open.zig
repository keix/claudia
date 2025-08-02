const syscall = @import("syscall");
const sysno = @import("sysno");

// File open flags (can be ORed together)
pub const O_RDONLY: usize = 0; // open for reading only
pub const O_WRONLY: usize = 1; // open for writing only
pub const O_RDWR: usize = 2; // open for reading and writing
pub const O_CREAT: usize = 64; // create file if it does not exist
pub const O_EXCL: usize = 128; // error if O_CREAT and file exists
pub const O_TRUNC: usize = 512; // truncate file to zero length if it exists
pub const O_APPEND: usize = 1024; // append on each write
pub const O_NONBLOCK: usize = 2048; // non-blocking mode
pub const O_DIRECTORY: usize = 65536; // fail if not a directory
pub const O_CLOEXEC: usize = 524288; // close on exec

// File mode (permission bits)
pub const S_IRWXU: usize = 0o700; // read, write, execute: owner
pub const S_IRUSR: usize = 0o400; // read: owner
pub const S_IWUSR: usize = 0o200; // write: owner
pub const S_IXUSR: usize = 0o100; // execute: owner

pub const S_IRWXG: usize = 0o070; // read, write, execute: group
pub const S_IRGRP: usize = 0o040; // read: group
pub const S_IWGRP: usize = 0o020; // write: group
pub const S_IXGRP: usize = 0o010; // execute: group

pub const S_IRWXO: usize = 0o007; // read, write, execute: others
pub const S_IROTH: usize = 0o004; // read: others
pub const S_IWOTH: usize = 0o002; // write: others
pub const S_IXOTH: usize = 0o001; // execute: others

// Special value for openat to use current working directory
pub const AT_FDCWD: isize = -100;

/// Opens a file or directory using the raw `openat` syscall.
/// On RISC-V, the traditional `open` syscall is not available, so we use `openat` with AT_FDCWD.
///
/// - `path`: pointer to a null-terminated string (must be valid memory)
/// - `flags`: file open flags (e.g., `O_RDONLY`, `O_CREAT`, etc.)
/// - `mode`: file permission mode (used only if `O_CREAT` is set)
///
/// Returns: a new file descriptor on success, or a negative error code on failure.
pub fn open(path: *const u8, flags: usize, mode: usize) isize {
    // Use openat with AT_FDCWD to emulate open behavior
    return syscall.syscall4(sysno.sys_openat, @bitCast(@as(isize, AT_FDCWD)), @intFromPtr(path), flags, mode);
}
