// kernel/syscalls/time.zig - Time-related system calls
const std = @import("std");
const abi = @import("abi");
const process = @import("../process/core.zig");
const copy = @import("../user/copy.zig");
const csr = @import("../arch/riscv/csr.zig");
const config = @import("../config.zig");

// Simple time counter - seconds since boot
// In a real system, this would be backed by RTC or network time
var boot_time: i64 = 1700000000; // Arbitrary epoch time for testing
var boot_cycles: u64 = 0;

// Get current time (seconds since epoch)
pub fn sys_time(tloc: usize) isize {
    // Initialize boot_cycles on first call
    if (boot_cycles == 0) {
        boot_cycles = csr.readTime();
    }

    // Read current timer value
    const current_cycles = csr.readTime();
    const elapsed_cycles = current_cycles - boot_cycles;

    // Assume 10MHz timer frequency (QEMU default)
    // Convert cycles to seconds
    const elapsed_seconds = @divTrunc(elapsed_cycles, config.Timer.FREQUENCY_HZ);
    const current_time = boot_time + @as(i64, @intCast(elapsed_seconds));

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

    // Initialize boot_cycles on first call
    if (boot_cycles == 0) {
        boot_cycles = csr.readTime();
    }

    // Read current timer value
    const current_cycles = csr.readTime();
    const elapsed_cycles = current_cycles - boot_cycles;

    // Calculate seconds and nanoseconds
    const elapsed_seconds = @divTrunc(elapsed_cycles, config.Timer.FREQUENCY_HZ);
    const remaining_cycles = @mod(elapsed_cycles, config.Timer.FREQUENCY_HZ);
    const nanoseconds = remaining_cycles * config.Timer.NANOSECONDS_PER_CYCLE; // Convert to nanoseconds

    const timespec = packed struct {
        tv_sec: i64,
        tv_nsec: i64,
    };

    var ts = timespec{
        .tv_sec = boot_time + @as(i64, @intCast(elapsed_seconds)),
        .tv_nsec = @as(i64, @intCast(nanoseconds)),
    };

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
