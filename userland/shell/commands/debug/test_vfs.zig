// test_vfs - Test the Virtual File System
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    utils.writeStr("Testing VFS path resolution...\n\n");

    // Test various paths
    const test_paths = [_][]const u8{
        "/dev/console",
        "/dev/tty",
        "/dev/null", // Should fail
        "/", // Should fail with EISDIR
        "/dev", // Should fail with EISDIR
        "/nonexistent", // Should fail with ENOENT
    };

    for (test_paths) |path| {
        utils.writeStr("Opening '");
        utils.writeStr(path);
        utils.writeStr("': ");

        const fd = sys.open(@ptrCast(path.ptr), 0, 0);
        if (fd >= 0) {
            utils.writeStr("Success, fd=");
            writeNumber(@intCast(fd));
            utils.writeStr("\n");

            // Close it
            _ = sys.close(@intCast(fd));
        } else {
            utils.writeStr("Error ");
            writeNumber(@intCast(-fd));
            switch (-fd) {
                2 => utils.writeStr(" (ENOENT - No such file)"),
                19 => utils.writeStr(" (ENODEV - Device not supported)"),
                21 => utils.writeStr(" (EISDIR - Is a directory)"),
                38 => utils.writeStr(" (ENOSYS - Not implemented)"),
                else => {},
            }
            utils.writeStr("\n");
        }
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
