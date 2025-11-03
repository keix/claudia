// Simple timer interrupt counter for debugging

var interrupt_count: u64 = 0;

pub fn increment() void {
    interrupt_count += 1;
}

pub fn get() u64 {
    return interrupt_count;
}