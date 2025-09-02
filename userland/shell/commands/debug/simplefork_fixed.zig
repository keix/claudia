// Fixed simple fork test - uses local buffers to avoid race conditions
const sys = @import("sys");
const utils = @import("shell/utils");

// Local number to string conversion to avoid global buffer issues
fn numberToStr(comptime T: type, value: T, buf: []u8) []const u8 {
    if (value == 0) {
        if (buf.len > 0) {
            buf[0] = '0';
            return buf[0..1];
        }
        return "";
    }

    var n = if (value < 0) -value else value;
    var i: usize = 0;

    // Generate digits in reverse
    while (n > 0 and i < buf.len) : (i += 1) {
        buf[i] = '0' + @as(u8, @intCast(@mod(n, 10)));
        n = @divFloor(n, 10);
    }

    // Add negative sign if needed
    if (value < 0 and i < buf.len) {
        buf[i] = '-';
        i += 1;
    }

    // Reverse the string
    var j: usize = 0;
    while (j < i / 2) : (j += 1) {
        const temp = buf[j];
        buf[j] = buf[i - 1 - j];
        buf[i - 1 - j] = temp;
    }

    return buf[0..i];
}

pub fn main(args: *const utils.Args) void {
    _ = args;

    utils.writeStr("Before fork\n");

    const pid = sys.fork() catch {
        utils.writeStr("Fork failed!\n");
        return;
    };

    if (pid == 0) {
        // Child process
        utils.writeStr("Child: Hello from child!\n");
        utils.writeStr("Child: PID = ");

        // Use local buffer for PID conversion
        var child_buf: [12]u8 = undefined;
        const child_pid = sys.getpid();
        utils.writeStr(numberToStr(isize, child_pid, &child_buf));

        utils.writeStr("\n");
        utils.writeStr("Child: Exiting\n");
        sys.exit(0);
    } else {
        // Parent process
        utils.writeStr("Parent: Fork returned PID = ");

        // Use local buffer for PID conversion
        var parent_buf: [12]u8 = undefined;
        utils.writeStr(numberToStr(isize, pid, &parent_buf));

        utils.writeStr("\n");
        utils.writeStr("Parent: Continuing\n");
    }

    utils.writeStr("After fork (only parent should see this)\n");
}
