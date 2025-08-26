// test_file - Test creating and writing to files
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    utils.writeStr("Testing file creation and I/O...\n\n");

    // Test 1: Create and write to a file
    utils.writeStr("1. Creating /test.txt with O_CREAT...\n");
    const fd = sys.open(@ptrCast("/test.txt"), sys.abi.O_CREAT | sys.abi.O_WRONLY, 0o644);
    if (fd < 0) {
        utils.writeStr("ERROR: Failed to create file, error=");
        writeNumber(@intCast(-fd));
        utils.writeStr("\n");
        return;
    }
    utils.writeStr("   Success! fd=");
    writeNumber(@intCast(fd));
    utils.writeStr("\n");

    // Test 2: Write to the file
    utils.writeStr("2. Writing 'Hello, World!' to file...\n");
    const msg = "Hello, World!\n";
    const written = sys.write(@intCast(fd), @ptrCast(msg.ptr), msg.len);
    if (written == msg.len) {
        utils.writeStr("   Success! Wrote ");
        writeNumber(@intCast(written));
        utils.writeStr(" bytes\n");
    } else {
        utils.writeStr("   Failed: expected ");
        writeNumber(msg.len);
        utils.writeStr(" bytes, wrote ");
        writeNumber(@intCast(written));
        utils.writeStr("\n");
    }

    // Test 3: Close the file
    utils.writeStr("3. Closing file...\n");
    const close_result = sys.close(@intCast(fd));
    if (close_result == 0) {
        utils.writeStr("   Success!\n");
    } else {
        utils.writeStr("   Failed: error=");
        writeNumber(@intCast(-close_result));
        utils.writeStr("\n");
    }

    // Test 4: Re-open and read
    utils.writeStr("4. Re-opening file for reading...\n");
    const fd2 = sys.open(@ptrCast("/test.txt"), sys.abi.O_RDONLY, 0);
    if (fd2 < 0) {
        utils.writeStr("   ERROR: Failed to open, error=");
        writeNumber(@intCast(-fd2));
        utils.writeStr("\n");
        return;
    }
    utils.writeStr("   Success! fd=");
    writeNumber(@intCast(fd2));
    utils.writeStr("\n");

    // Test 5: Read from file
    utils.writeStr("5. Reading from file...\n");
    var buffer: [32]u8 = undefined;
    const read_bytes = sys.read(@intCast(fd2), @ptrCast(&buffer), buffer.len);
    if (read_bytes > 0) {
        utils.writeStr("   Success! Read ");
        writeNumber(@intCast(read_bytes));
        utils.writeStr(" bytes: ");
        utils.writeStr(buffer[0..@intCast(read_bytes)]);
    } else if (read_bytes == 0) {
        utils.writeStr("   EOF reached\n");
    } else {
        utils.writeStr("   Failed: error=");
        writeNumber(@intCast(-read_bytes));
        utils.writeStr("\n");
    }

    _ = sys.close(@intCast(fd2));

    utils.writeStr("\nFile I/O test completed!\n");
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
