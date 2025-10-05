// Simple timer interrupt test - minimal implementation
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    utils.writeStr("Timer interrupt test (5 seconds)\n");

    // Get initial timer count via debug syscall
    const start_count = asm volatile ("li a7, 999; ecall; mv %[ret], a0"
        : [ret] "=r" (-> usize),
        :
        : "a0", "a7"
    );
    utils.writeStr("Initial timer interrupts: ");
    printNumber(start_count);
    utils.writeStr("\n");

    // Sleep for 5 seconds (should see ~500 interrupts at 100Hz)
    for (0..5) |i| {
        utils.writeStr("Second ");
        printNumber(i + 1);
        utils.writeStr("...\n");

        // Use nanosleep for accurate 1 second delay
        var req = sys.timespec{
            .tv_sec = 1,
            .tv_nsec = 0,
        };
        _ = sys.nanosleep(&req, null);
    }

    // Get final timer count
    const end_count = asm volatile ("li a7, 999; ecall; mv %[ret], a0"
        : [ret] "=r" (-> usize),
        :
        : "a0", "a7"
    );
    utils.writeStr("Final timer interrupts: ");
    printNumber(end_count);
    utils.writeStr("\n");

    const diff = end_count - start_count;
    utils.writeStr("Interrupts during test: ");
    printNumber(diff);
    utils.writeStr("\n");

    if (diff > 400 and diff < 600) {
        utils.writeStr("✓ Timer working correctly (100Hz)\n");
    } else if (diff > 0) {
        utils.writeStr("⚠ Timer frequency incorrect\n");
    } else {
        utils.writeStr("✗ Timer not working\n");
    }
}

fn printNumber(n: usize) void {
    if (n == 0) {
        utils.writeStr("0");
        return;
    }

    var buf: [32]u8 = undefined;
    var i: usize = 0;
    var num = n;

    while (num > 0) : (num /= 10) {
        buf[i] = @as(u8, @intCast(num % 10)) + '0';
        i += 1;
    }

    // Reverse and print
    while (i > 0) {
        i -= 1;
        var tmp: [1]u8 = .{buf[i]};
        utils.writeStr(&tmp);
    }
}
