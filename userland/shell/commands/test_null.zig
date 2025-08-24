// test_null - Test /dev/null device
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;
    
    utils.writeStr("Testing /dev/null device...\n");
    
    // Test 1: Open /dev/null
    const fd = sys.open(@ptrCast("/dev/null"), 0, 0);
    if (fd < 0) {
        utils.writeStr("ERROR: Failed to open /dev/null, error=");
        writeNumber(@intCast(-fd));
        utils.writeStr("\n");
        return;
    }
    
    utils.writeStr("Successfully opened /dev/null, fd=");
    writeNumber(@intCast(fd));
    utils.writeStr("\n");
    
    // Test 2: Write to /dev/null
    const msg = "This message goes to the void!\n";
    const written = sys.write(@intCast(fd), @ptrCast(msg.ptr), msg.len);
    if (written == msg.len) {
        utils.writeStr("Write test passed: ");
        writeNumber(@intCast(written));
        utils.writeStr(" bytes discarded\n");
    } else {
        utils.writeStr("Write test failed: expected ");
        writeNumber(msg.len);
        utils.writeStr(", got ");
        writeNumber(@intCast(written));
        utils.writeStr("\n");
    }
    
    // Test 3: Read from /dev/null (should return EOF)
    var buffer: [32]u8 = undefined;
    const read_result = sys.read(@intCast(fd), @ptrCast(&buffer), buffer.len);
    if (read_result == 0) {
        utils.writeStr("Read test passed: got EOF\n");
    } else {
        utils.writeStr("Read test failed: expected 0, got ");
        writeNumber(@intCast(read_result));
        utils.writeStr("\n");
    }
    
    // Test 4: Close /dev/null
    const close_result = sys.close(@intCast(fd));
    if (close_result == 0) {
        utils.writeStr("Close test passed\n");
    } else {
        utils.writeStr("Close test failed, error=");
        writeNumber(@intCast(-close_result));
        utils.writeStr("\n");
    }
    
    utils.writeStr("\nAll /dev/null tests completed\n");
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