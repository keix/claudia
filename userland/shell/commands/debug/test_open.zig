// test_open - Test the open system call
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    utils.writeStr("Testing open system call...\n");

    // Test opening /dev/console
    const fd = sys.open(@ptrCast("/dev/console"), 0, 0);
    if (fd >= 0) {
        utils.writeStr("Successfully opened /dev/console, fd=");
        writeNumber(@intCast(fd));
        utils.writeStr("\n");

        // Try to write to it
        const msg = "Hello from opened console!\n";
        const written = sys.write(@intCast(fd), @ptrCast(msg.ptr), msg.len);
        if (written > 0) {
            utils.writeStr("Write successful\n");
        }

        // Close it
        const close_result = sys.close(@intCast(fd));
        if (close_result == 0) {
            utils.writeStr("Successfully closed fd\n");
        } else {
            utils.writeStr("Failed to close fd, error=");
            writeNumber(@intCast(-close_result));
            utils.writeStr("\n");
        }
    } else {
        utils.writeStr("Failed to open /dev/console, error=");
        writeNumber(@intCast(-fd));
        utils.writeStr("\n");
    }

    // Test opening non-existent file
    const fd2 = sys.open(@ptrCast("/does/not/exist"), 0, 0);
    if (fd2 < 0) {
        utils.writeStr("Expected error for non-existent file, error=");
        writeNumber(@intCast(-fd2));
        utils.writeStr("\n");
    }

    // Test closing standard file descriptors (should fail)
    utils.writeStr("\nTesting close on stdin/stdout/stderr:\n");
    const close_stdin = sys.close(0);
    if (close_stdin < 0) {
        utils.writeStr("Correctly refused to close stdin, error=");
        writeNumber(@intCast(-close_stdin));
        utils.writeStr("\n");
    }

    const close_stdout = sys.close(1);
    if (close_stdout < 0) {
        utils.writeStr("Correctly refused to close stdout, error=");
        writeNumber(@intCast(-close_stdout));
        utils.writeStr("\n");
    }
}

fn writeNumber(n: usize) void {
    if (n == 0) {
        utils.writeStr("0");
        return;
    }

    var buffer: [20]u8 = undefined;
    var i: usize = 0;
    var num = n;

    // Convert to string (backwards)
    while (num > 0 and i < buffer.len) {
        buffer[i] = @intCast('0' + (num % 10));
        num /= 10;
        i += 1;
    }

    // Print in correct order
    while (i > 0) {
        i -= 1;
        var ch: [1]u8 = .{buffer[i]};
        utils.writeStr(&ch);
    }
}
