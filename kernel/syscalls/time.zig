// kernel/syscalls/time.zig - Time-related system calls
const std = @import("std");
const abi = @import("abi");
const process = @import("../process/core.zig");
const copy = @import("../user/copy.zig");

// Simple time counter - seconds since boot
// In a real system, this would be backed by RTC or network time
var boot_time: i64 = 1700000000; // Arbitrary epoch time for testing
var time_offset: i64 = 0;

// Get current time (seconds since epoch)
pub fn sys_time(tloc: usize) isize {
    // Calculate current time (just increment for now)
    // In real implementation, this would read from RTC or timer
    const current_time = boot_time + time_offset;
    time_offset += 1; // Simple increment for testing

    // If tloc is provided, write the time to user memory
    if (tloc != 0) {
        // Copy to user space
        _ = copy.copyout(tloc, std.mem.asBytes(&current_time)) catch {
            return abi.EFAULT;
        };
    }

    return @intCast(current_time);
}

// Get time with nanosecond precision
pub fn sys_clock_gettime(clockid: usize, tp: usize) isize {
    _ = clockid; // TODO: Support different clock types

    if (tp == 0) {
        return abi.EINVAL;
    }

    const timespec = packed struct {
        tv_sec: i64,
        tv_nsec: i64,
    };

    var ts = timespec{
        .tv_sec = boot_time + time_offset,
        .tv_nsec = 0, // TODO: Add nanosecond precision
    };
    time_offset += 1;

    _ = copy.copyout(tp, std.mem.asBytes(&ts)) catch {
        return abi.EFAULT;
    };

    return 0;
}

// Sleep for specified time
pub fn sys_nanosleep(req: usize, rem: usize) isize {
    _ = req;
    _ = rem;
    // TODO: Implement actual sleep
    // For now, just yield the CPU
    process.Scheduler.yield();
    return 0;
}
