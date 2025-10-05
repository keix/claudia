// RISC-V Timer Driver for Process Scheduling
// Uses machine timer (mtime/mtimecmp) through SBI calls

const std = @import("std");
const csr = @import("../arch/riscv/csr.zig");
const uart = @import("../driver/uart/core.zig");
const proc = @import("../process/core.zig");

// Timer frequency (5MHz effective on QEMU)
const TIMER_FREQ: u64 = 5_000_000;

// Timer interval for scheduling (10ms)
const TIMER_INTERVAL_MS: u64 = 10;
const TIMER_INTERVAL_CYCLES: u64 = TIMER_FREQ * TIMER_INTERVAL_MS / 1000;

// SBI timer extension
const SBI_EXT_TIME: i64 = 0x54494D45; // "TIME"
const SBI_EXT_TIME_SET_TIMER: i64 = 0;

// SBI call for timer (using legacy SBI call)
fn sbi_set_timer(stime_value: u64) void {
    // Legacy SBI timer call: a7 = 0, a0 = timer value
    asm volatile (
        \\mv a0, %[val]
        \\li a7, 0           # SBI legacy timer extension
        \\ecall
        :
        : [val] "r" (stime_value),
        : "a0", "a7", "memory"
    );
}

// Read machine time (through rdtime instruction)
pub fn readTime() u64 {
    return asm volatile ("rdtime %[ret]"
        : [ret] "=r" (-> u64),
    );
}

// Initialize timer
pub fn init() void {
    uart.puts("Timer: Initializing...\n");

    // Set first timer interrupt
    const current_time = readTime();
    const next_time = current_time + TIMER_INTERVAL_CYCLES;
    sbi_set_timer(next_time);

    // Enable supervisor timer interrupts
    const sie = csr.csrr(csr.CSR.sie);
    csr.csrw(csr.CSR.sie, sie | (1 << 5)); // STIE bit

    uart.puts("Timer: Initialized\n");
}

// Handle timer interrupt - called from trap handler
pub fn handleInterrupt() void {
    // Increment global counter for debugging
    const counter = @import("../time/counter.zig");
    counter.increment();

    // Set next timer interrupt
    const current_time = readTime();
    const next_time = current_time + TIMER_INTERVAL_CYCLES;
    sbi_set_timer(next_time);

    // Trigger process scheduling
    proc.Scheduler.yield();
}

// Sleep for specified milliseconds (busy wait version)
pub fn sleepMs(ms: u64) void {
    const start = readTime();
    const cycles = ms * TIMER_FREQ / 1000;
    while (readTime() - start < cycles) {
        asm volatile ("nop");
    }
}
