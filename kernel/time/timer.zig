// Timer management for sleep and scheduling
const csr = @import("../arch/riscv/csr.zig");
const proc = @import("../process/core.zig");
const config = @import("../config.zig");

// Timer tick interval (100Hz = 10ms per tick)
const TIMER_HZ: u64 = 100;
const CYCLES_PER_TICK: u64 = config.Timer.FREQUENCY_HZ / TIMER_HZ;

// Track sleeping processes and their wake times
const SleepEntry = struct {
    process: *proc.Process,
    wake_cycles: u64,
};

var sleep_list: [32]?SleepEntry = [_]?SleepEntry{null} ** 32;

// Initialize timer subsystem
pub fn init() void {
    // Set up first timer interrupt
    scheduleNextInterrupt();
}

// Schedule the next timer interrupt
fn scheduleNextInterrupt() void {
    // In S-mode, we need to use SBI calls or M-mode assistance for timer
    // For now, we'll rely on periodic checking in trap handler
    // Real implementation would set stimecmp or use SBI timer extension

    // Future: Calculate next interrupt time
    // const current = csr.readTime();
    // const next = current + CYCLES_PER_TICK;
    // sbi.setTimer(next);
}

// Add a process to sleep list
pub fn sleepUntil(process: *proc.Process, wake_cycles: u64) void {
    // Find free slot
    for (&sleep_list) |*entry| {
        if (entry.* == null) {
            entry.* = SleepEntry{
                .process = process,
                .wake_cycles = wake_cycles,
            };
            return;
        }
    }
}

// Check and wake sleeping processes
pub fn checkSleepers() void {
    const current_cycles = csr.readTime();

    for (&sleep_list) |*entry| {
        if (entry.*) |sleep_entry| {
            if (current_cycles >= sleep_entry.wake_cycles) {
                // Time to wake up
                proc.Scheduler.makeRunnable(sleep_entry.process);
                entry.* = null;
            }
        }
    }
}

// Called periodically from scheduler or trap handler
pub fn tick() void {
    checkSleepers();
    // Could also handle other periodic tasks here
}

