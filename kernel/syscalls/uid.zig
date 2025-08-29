// kernel/syscalls/uid.zig - User and group ID system calls
const defs = @import("abi");

// Get real user ID
pub fn sys_getuid() isize {
    // Single-user system - always return root (0)
    return 0;
}

// Get effective user ID
pub fn sys_geteuid() isize {
    // Single-user system - always return root (0)
    return 0;
}

// Get real group ID
pub fn sys_getgid() isize {
    // Single-user system - always return root (0)
    return 0;
}

// Get effective group ID
pub fn sys_getegid() isize {
    // Single-user system - always return root (0)
    return 0;
}

// Set user ID (not implemented)
pub fn sys_setuid(uid: usize) isize {
    _ = uid;
    // Single-user system - ignore but return success
    return 0;
}

// Set group ID (not implemented)
pub fn sys_setgid(gid: usize) isize {
    _ = gid;
    // Single-user system - ignore but return success
    return 0;
}
