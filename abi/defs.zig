// defs.zig - POSIX-style flags and constants
// Reference: man 2 open, man 2 chmod

// File open flags (can be ORed together)
pub const O_RDONLY = 0; // open for reading only
pub const O_WRONLY = 1; // open for writing only
pub const O_RDWR = 2; // open for reading and writing
pub const O_CREAT = 64; // create file if it does not exist
pub const O_EXCL = 128; // error if O_CREAT and file exists
pub const O_TRUNC = 512; // truncate file to zero length
pub const O_APPEND = 1024; // append on each write
pub const O_NONBLOCK = 2048; // non-blocking mode
pub const O_DIRECTORY = 65536; // fail if not a directory
pub const O_CLOEXEC = 524288; // close-on-exec

// File mode (permission bits)
pub const S_IRWXU = 0o700; // owner: read, write, execute
pub const S_IRUSR = 0o400; // owner: read
pub const S_IWUSR = 0o200; // owner: write
pub const S_IXUSR = 0o100; // owner: execute

pub const S_IRWXG = 0o070; // group: read, write, execute
pub const S_IRGRP = 0o040; // group: read
pub const S_IWGRP = 0o020; // group: write
pub const S_IXGRP = 0o010; // group: execute

pub const S_IRWXO = 0o007; // others: read, write, execute
pub const S_IROTH = 0o004; // others: read
pub const S_IWOTH = 0o002; // others: write
pub const S_IXOTH = 0o001; // others: execute

// lseek() constants
pub const SEEK_SET = 0;
pub const SEEK_CUR = 1;
pub const SEEK_END = 2;

// Error codes (errno values) - negative values
pub const ENOSYS: isize = -38; // Function not implemented
pub const EBADF: isize = -9; // Bad file descriptor
pub const EFAULT: isize = -14; // Bad address
pub const EBUSY: isize = -16; // Device or resource busy
pub const EINVAL: isize = -22; // Invalid argument
pub const ESRCH: isize = -3; // No such process
pub const ENOMEM: isize = -12; // Out of memory
pub const EAGAIN: isize = -11; // Try again
pub const EMFILE: isize = -24; // Too many open files
pub const ENOENT: isize = -2; // No such file or directory
pub const ENODEV: isize = -19; // No such device
pub const EISDIR: isize = -21; // Is a directory
pub const ENOSPC: isize = -28; // No space left on device
pub const ENOTDIR: isize = -20; // Not a directory
pub const EIO: isize = -5; // I/O error
pub const ENAMETOOLONG: isize = -36; // File name too long
pub const ESPIPE: isize = -29; // Illegal seek
pub const ERANGE: isize = -34; // Result too large
