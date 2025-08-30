// ABI constants shared between kernel and userland
// These values must remain stable for binary compatibility

const std = @import("std");

// File system constants (POSIX-compatible)
pub const FileSystem = struct {
    // Seek whence values
    pub const SEEK_SET: u32 = 0;
    pub const SEEK_CUR: u32 = 1;
    pub const SEEK_END: u32 = 2;
    pub const SEEK_MAX: u32 = 2;

    // Maximum path length
    pub const PATH_MAX: usize = 256;

    // Maximum filename length
    pub const NAME_MAX: usize = 255;
};

// Time constants
pub const Time = struct {
    // Nanoseconds per second
    pub const NSEC_PER_SEC: u64 = 1_000_000_000;

    // Clock types (for clock_gettime)
    pub const CLOCK_REALTIME: u32 = 0;
    pub const CLOCK_MONOTONIC: u32 = 1;
};

// Process constants
pub const Process = struct {
    // Standard file descriptors
    pub const STDIN_FD: i32 = 0;
    pub const STDOUT_FD: i32 = 1;
    pub const STDERR_FD: i32 = 2;

    // Maximum number of file descriptors per process
    pub const MAX_FDS: usize = 256;
};

// Memory constants visible to userland
pub const Memory = struct {
    // Page size (must match hardware)
    pub const PAGE_SIZE: usize = 4096;

    // Stack size for user processes
    pub const USER_STACK_SIZE: usize = 4096; // 1 page
};
