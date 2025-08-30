// kernel/syscalls/time.zig - Time-related system calls
const std = @import("std");
const abi = @import("abi");
const process = @import("../process/core.zig");
const copy = @import("../user/copy.zig");
const csr = @import("../arch/riscv/csr.zig");
const config = @import("../config.zig");
const timer = @import("../time/timer.zig");

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

// Sleep queue for timed sleeps
pub var sleep_queue = process.WaitQ.init();

// Sleep for specified time
pub fn sys_nanosleep(req: usize, rem: usize) isize {
    // Read the requested sleep time
    const timespec = packed struct {
        tv_sec: i64,
        tv_nsec: i64,
    };

    var req_ts: timespec = undefined;
    _ = copy.copyin(std.mem.asBytes(&req_ts), req) catch {
        return abi.EFAULT;
    };

    // Validate nanoseconds
    if (req_ts.tv_nsec < 0 or req_ts.tv_nsec >= abi.consts.Time.NSEC_PER_SEC) {
        return abi.EINVAL;
    }

    // Calculate total sleep time in nanoseconds
    const total_ns = @as(u64, @intCast(req_ts.tv_sec)) * abi.consts.Time.NSEC_PER_SEC +
        @as(u64, @intCast(req_ts.tv_nsec));

    if (total_ns == 0) {
        // Sleep for 0 time - just yield
        process.Scheduler.yield();
        return 0;
    }

    // Get current timer value
    const start_cycles = csr.readTime();

    // Calculate wake up time in cycles
    const sleep_cycles = total_ns / config.Timer.NANOSECONDS_PER_CYCLE;
    const wake_cycles = start_cycles + sleep_cycles;

    // Get current process
    const current = process.Scheduler.getCurrentProcess() orelse return abi.ESRCH;

    // Add process to timer sleep list
    timer.sleepUntil(current, wake_cycles);

    // Mark process as not runnable and switch away
    current.state = .SLEEPING;
    process.Scheduler.scheduleNext();

    // When we return here, we've been woken up
    // Check if we were interrupted or time expired
    const current_cycles = csr.readTime();

    // If rem is provided and we were interrupted early, write remaining time
    if (rem != 0) {
        if (current_cycles < wake_cycles) {
            // Interrupted early - calculate remaining time
            const remaining_cycles = wake_cycles - current_cycles;
            const remaining_ns = remaining_cycles * config.Timer.NANOSECONDS_PER_CYCLE;

            var rem_ts = timespec{
                .tv_sec = @intCast(remaining_ns / abi.consts.Time.NSEC_PER_SEC),
                .tv_nsec = @intCast(remaining_ns % abi.consts.Time.NSEC_PER_SEC),
            };
            _ = copy.copyout(rem, std.mem.asBytes(&rem_ts)) catch {};

            // Return interrupted
            return abi.EINTR;
        } else {
            // Completed normally
            const zero_ts = timespec{
                .tv_sec = 0,
                .tv_nsec = 0,
            };
            _ = copy.copyout(rem, std.mem.asBytes(&zero_ts)) catch {};
        }
    }

    return 0;
}
