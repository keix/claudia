// Global timer interrupt counter for debugging
pub var timer_interrupt_count: u64 = 0;

pub fn increment() void {
    timer_interrupt_count += 1;
}

pub fn get() u64 {
    return timer_interrupt_count;
}
