// kernel/syscalls/api.zig - High-level syscall API for Lisp
const std = @import("std");
const dispatch = @import("dispatch.zig");
const abi = @import("abi");

// File operations
pub fn open(path: []const u8, flags: u32) isize {
    return dispatch.call(abi.sysno.sys_openat, @as(usize, @bitCast(@as(isize, -100))), @intFromPtr(path.ptr), flags, 0, 0);
}

pub fn read(fd: i32, buf: []u8) isize {
    return dispatch.call(abi.sysno.sys_read, @intCast(fd), @intFromPtr(buf.ptr), buf.len, 0, 0);
}

pub fn write(fd: i32, buf: []const u8) isize {
    return dispatch.call(abi.sysno.sys_write, @intCast(fd), @intFromPtr(buf.ptr), buf.len, 0, 0);
}

pub fn close(fd: i32) isize {
    return dispatch.call(abi.sysno.sys_close, @intCast(fd), 0, 0, 0, 0);
}

// Process operations
pub fn exit(status: i32) noreturn {
    _ = dispatch.call(abi.sysno.sys_exit, @intCast(status), 0, 0, 0, 0);
    unreachable;
}

pub fn fork() isize {
    return dispatch.call(abi.sysno.sys_fork, 0, 0, 0, 0, 0);
}

pub fn yield() isize {
    return dispatch.call(abi.sysno.sys_sched_yield, 0, 0, 0, 0, 0);
}

// Directory operations
pub fn readdir(fd: i32, dirents: []u8) isize {
    return dispatch.call(abi.sysno.sys_getdents64, @intCast(fd), @intFromPtr(dirents.ptr), dirents.len, 0, 0);
}

// String helpers for Lisp
pub fn writeString(fd: i32, str: []const u8) isize {
    return write(fd, str);
}

pub fn println(str: []const u8) isize {
    const stdout = 1;
    const result = write(stdout, str);
    if (result > 0) {
        _ = write(stdout, "\n");
    }
    return result;
}