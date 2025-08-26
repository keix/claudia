// test_ramdisk - Test RAM disk functionality
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    utils.writeStr("Testing RAM disk...\n");

    // Try to open /dev/ramdisk
    const fd = sys.open(@ptrCast("/dev/ramdisk\x00".ptr), 0, 0);
    if (fd < 0) {
        utils.writeStr("Error: cannot open /dev/ramdisk (");
        writeNumber(@intCast(-fd));
        utils.writeStr(")\n");
        return;
    }

    utils.writeStr("Successfully opened /dev/ramdisk as fd ");
    writeNumber(@intCast(fd));
    utils.writeStr("\n");

    // Test write
    const test_data = "Hello, RAM disk!\n";
    const write_result = sys.write(@intCast(fd), @ptrCast(test_data.ptr), test_data.len);
    utils.writeStr("Write test: wrote ");
    writeNumber(@intCast(write_result));
    utils.writeStr(" bytes\n");

    // Test read (seek back to beginning would be needed for real test)
    var read_buf: [32]u8 = undefined;
    const read_result = sys.read(@intCast(fd), @ptrCast(&read_buf), read_buf.len);
    utils.writeStr("Read test: read ");
    writeNumber(@intCast(read_result));
    utils.writeStr(" bytes\n");

    // Close the device
    _ = sys.close(@intCast(fd));

    utils.writeStr("RAM disk test completed.\n");
}

fn writeNumber(n: usize) void {
    if (n == 0) {
        utils.writeStr("0");
        return;
    }

    var buffer: [20]u8 = undefined;
    var i: usize = 0;
    var num = n;

    while (num > 0 and i < buffer.len) {
        buffer[i] = @intCast('0' + (num % 10));
        num /= 10;
        i += 1;
    }

    while (i > 0) {
        i -= 1;
        var ch: [1]u8 = .{buffer[i]};
        utils.writeStr(&ch);
    }
}
