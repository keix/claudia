// userland/syscalls/uid/uid.zig - User and group ID syscall wrappers
const syscall = @import("syscall");
const abi = @import("abi");

// Get real user ID
pub fn getuid() i32 {
    const result = syscall.syscall0(abi.sysno.sys_getuid);
    return @intCast(result);
}

// Get effective user ID
pub fn geteuid() i32 {
    const result = syscall.syscall0(abi.sysno.sys_geteuid);
    return @intCast(result);
}

// Get real group ID
pub fn getgid() i32 {
    const result = syscall.syscall0(abi.sysno.sys_getgid);
    return @intCast(result);
}

// Get effective group ID
pub fn getegid() i32 {
    const result = syscall.syscall0(abi.sysno.sys_getegid);
    return @intCast(result);
}
