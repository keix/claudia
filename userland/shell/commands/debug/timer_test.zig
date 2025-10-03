const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    utils.writeStr("Timer interrupt test\n");
    utils.writeStr("Sleeping for 5 seconds...\n");

    // Get current time
    const start_time = sys.time(null);

    // Sleep for 5 seconds
    var req = sys.timespec{
        .tv_sec = 5,
        .tv_nsec = 0,
    };
    _ = sys.nanosleep(&req, null);

    // Get end time
    const end_time = sys.time(null);
    const elapsed = end_time - start_time;

    utils.writeStr("Woke up! Elapsed time: ");
    utils.writeDec(@intCast(elapsed));
    utils.writeStr(" ticks\n");

    // Test timer interrupts by doing busy work
    utils.writeStr("\nTesting timer preemption (busy loop for 3 seconds)...\n");
    const busy_start = sys.time(null);

    // Busy loop that should be preempted by timer interrupts
    while (true) {
        const now = sys.time(null);
        if (now - busy_start >= 3) break;

        // Do some work to keep CPU busy
        var sum: u64 = 0;
        for (0..1000) |i| {
            sum +%= i;
        }
        // Prevent optimization
        asm volatile (""
            :
            : [s] "r" (sum),
            : "memory"
        );
    }

    const busy_end = sys.time(null);
    utils.writeStr("Busy loop completed. Time: ");
    utils.writeDec(@intCast(busy_end - busy_start));
    utils.writeStr(" ticks\n");

    utils.writeStr("\nTimer test completed successfully!\n");
}
