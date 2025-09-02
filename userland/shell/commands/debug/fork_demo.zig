// Simple fork demo - parent and child print alternating messages
const sys = @import("sys");
const utils = @import("shell/utils");

fn numberToStr(num: u64, buf: []u8) []u8 {
    if (num == 0) {
        buf[0] = '0';
        return buf[0..1];
    }

    var n = num;
    var i: usize = 0;
    while (n > 0) : (n /= 10) {
        buf[i] = @as(u8, @intCast(n % 10)) + '0';
        i += 1;
    }

    // Reverse the string
    var j: usize = 0;
    while (j < i / 2) : (j += 1) {
        const tmp = buf[j];
        buf[j] = buf[i - j - 1];
        buf[i - j - 1] = tmp;
    }

    return buf[0..i];
}

pub fn main(args: *const utils.Args) void {
    _ = args;

    const my_pid = sys.getpid();

    utils.writeStr("Process ");
    var pidbuf: [32]u8 = undefined;
    utils.writeStr(numberToStr(@as(u64, @intCast(my_pid)), &pidbuf));
    utils.writeStr(" starting fork demo\n");

    const pid = sys.fork() catch |err| {
        utils.writeStr("Error: fork failed with ");
        switch (err) {
            error.ProcessLimitReached => utils.writeStr("ProcessLimitReached\n"),
            error.OutOfMemory => utils.writeStr("OutOfMemory\n"),
            error.SystemCallNotImplemented => utils.writeStr("SystemCallNotImplemented\n"),
            error.NoSuchProcess => utils.writeStr("NoSuchProcess\n"),
            error.InvalidArgument => utils.writeStr("InvalidArgument\n"),
            error.UnknownError => utils.writeStr("UnknownError\n"),
        }
        return;
    };

    if (pid == 0) {
        // Child process
        utils.writeStr("C"); // Simple marker
        sys.exit(0);
    } else {
        // Parent process
        for (0..5) |i| {
            utils.writeStr("Parent: message ");
            var numbuf: [32]u8 = undefined;
            utils.writeStr(numberToStr(i + 1, &numbuf));
            utils.writeStr("\n");

            // Yield to allow child to run
            _ = sys.sched_yield();
        }
        utils.writeStr("Parent: done!\n");
    }
}
