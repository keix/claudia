// unlinkat syscall wrapper
const syscall = @import("syscall");
const sysno = @import("abi").sysno;

pub const AT_FDCWD: isize = -100;
pub const AT_REMOVEDIR: u32 = 0x200;

pub fn unlinkat(dirfd: isize, pathname: [*:0]const u8, flags: u32) isize {
    return syscall.syscall3(sysno.sys_unlinkat, @as(usize, @bitCast(dirfd)), @intFromPtr(pathname), flags);
}

// Convenience wrapper for regular unlink
pub fn unlink(pathname: [*:0]const u8) isize {
    return unlinkat(AT_FDCWD, pathname, 0);
}

// Convenience wrapper for rmdir
pub fn rmdir(pathname: [*:0]const u8) isize {
    return unlinkat(AT_FDCWD, pathname, AT_REMOVEDIR);
}
