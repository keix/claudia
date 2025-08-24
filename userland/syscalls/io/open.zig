const syscall = @import("syscall");
const abi = @import("abi");
const defs = abi.types;

// Re-export flags from abi/defs.zig
pub const O_RDONLY = defs.O_RDONLY;
pub const O_WRONLY = defs.O_WRONLY;
pub const O_RDWR = defs.O_RDWR;
pub const O_CREAT = defs.O_CREAT;
pub const O_EXCL = defs.O_EXCL;
pub const O_TRUNC = defs.O_TRUNC;
pub const O_APPEND = defs.O_APPEND;
pub const O_NONBLOCK = defs.O_NONBLOCK;
pub const O_DIRECTORY = defs.O_DIRECTORY;
pub const O_CLOEXEC = defs.O_CLOEXEC;

// Re-export file mode bits from abi/defs.zig
pub const S_IRWXU = defs.S_IRWXU;
pub const S_IRUSR = defs.S_IRUSR;
pub const S_IWUSR = defs.S_IWUSR;
pub const S_IXUSR = defs.S_IXUSR;
pub const S_IRWXG = defs.S_IRWXG;
pub const S_IRGRP = defs.S_IRGRP;
pub const S_IWGRP = defs.S_IWGRP;
pub const S_IXGRP = defs.S_IXGRP;
pub const S_IRWXO = defs.S_IRWXO;
pub const S_IROTH = defs.S_IROTH;
pub const S_IWOTH = defs.S_IWOTH;
pub const S_IXOTH = defs.S_IXOTH;

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
    return syscall.syscall4(abi.sysno.sys_openat, @bitCast(@as(isize, AT_FDCWD)), @intFromPtr(path), flags, mode);
}
