// test_file - Test creating and writing to files
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    utils.writeStr("Testing file creation (mock for now)...\n");

    // For now, we'll just test that regular files return ENOENT (file not found)
    // since file creation is not implemented yet
    const fd = sys.open(@ptrCast("/test.txt"), sys.abi.O_CREAT | sys.abi.O_WRONLY, 0o644);
    if (fd < 0) {
        const error_num = @as(usize, @intCast(-fd));
        utils.writeStr("Expected error for regular file: ");

        // Debug: directly print the error number
        if (error_num == 2) {
            utils.writeStr("2 (ENOENT - File not found, creation not implemented)\n");
        } else if (error_num == 38) {
            utils.writeStr("38 (ENOSYS - Not implemented)\n");
        } else {
            // For other errors, try to display the number
            utils.writeStr("error=");
            writeNumber(error_num);
            utils.writeStr(" (Unexpected error)\n");
        }
    } else {
        utils.writeStr("Unexpected success opening regular file\n");
        _ = sys.close(@intCast(fd));
    }

    utils.writeStr("\nOnce implemented, this will:\n");
    utils.writeStr("1. Create /test.txt\n");
    utils.writeStr("2. Write 'Hello, World!' to it\n");
    utils.writeStr("3. Close the file\n");
    utils.writeStr("4. Re-open and read contents\n");
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
