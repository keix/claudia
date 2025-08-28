// userland/syscalls/time/time.zig - time(2) wrapper
const syscall = @import("syscall");
const abi = @import("abi");

// Get current time (seconds since epoch)
pub fn time(tloc: ?*i64) i64 {
    const tloc_addr = if (tloc) |t| @intFromPtr(t) else 0;
    const result = syscall.syscall1(abi.sysno.sys_time, tloc_addr);
    return @intCast(result);
}

// Get time with nanosecond precision
pub const timespec = struct {
    tv_sec: i64,
    tv_nsec: i64,
};

pub fn clock_gettime(clockid: i32, tp: *timespec) i32 {
    const result = syscall.syscall2(abi.sysno.sys_clock_gettime, @as(usize, @intCast(clockid)), @intFromPtr(tp));
    if (result < 0) {
        return @intCast(result);
    }
    return 0;
}

// Sleep for specified time
pub fn nanosleep(req: *const timespec, rem: ?*timespec) i32 {
    const rem_addr = if (rem) |r| @intFromPtr(r) else 0;
    const result = syscall.syscall2(abi.sysno.sys_nanosleep, @intFromPtr(req), rem_addr);
    if (result < 0) {
        return @intCast(result);
    }
    return 0;
}
