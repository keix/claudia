// Common file system types and constants

// File types
pub const FileType = enum {
    REGULAR, // Regular file
    DEVICE, // Device file (character/block)
    PIPE, // Named pipe (FIFO)
    SOCKET, // Socket
    DIRECTORY, // Directory
};

// File permissions (Unix-style)
pub const FileMode = struct {
    pub const IRUSR: u16 = 0o400; // Owner read
    pub const IWUSR: u16 = 0o200; // Owner write
    pub const IXUSR: u16 = 0o100; // Owner execute
    pub const IRGRP: u16 = 0o040; // Group read
    pub const IWGRP: u16 = 0o020; // Group write
    pub const IXGRP: u16 = 0o010; // Group execute
    pub const IROTH: u16 = 0o004; // Other read
    pub const IWOTH: u16 = 0o002; // Other write
    pub const IXOTH: u16 = 0o001; // Other execute
};

// File descriptor type
pub const FD = i32;

// Maximum number of open files
pub const MAX_OPEN_FILES: usize = 64;
