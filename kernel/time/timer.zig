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
pub fn scheduleNextInterrupt() void {
    const timer_driver = @import("../driver/timer.zig");
    const current_time = timer_driver.readTime();
    const next_time = current_time + CYCLES_PER_TICK;

    // Use legacy SBI call to set timer
    asm volatile (
        \\mv a0, %[val]
        \\li a7, 0           # SBI legacy timer extension
        \\ecall
        :
        : [val] "r" (next_time),
        : "a0", "a7", "memory"
    );
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
