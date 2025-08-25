// cat - Concatenate and display files
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    // Check if filename provided
    if (args.argc < 2) {
        utils.writeStr("Usage: cat <filename>\n");
        return;
    }

    // Process each file argument
    var i: usize = 1;
    while (i < args.argc) : (i += 1) {
        const filename = args.argv[i];
        catFile(filename);
    }
}

fn catFile(filename: []const u8) void {
    // Open file for reading
    const fd = sys.open(@ptrCast(filename.ptr), sys.abi.O_RDONLY, 0);
    if (fd < 0) {
        utils.writeStr("cat: ");
        utils.writeStr(filename);
        utils.writeStr(": ");
        switch (-fd) {
            2 => utils.writeStr("No such file or directory"),
            21 => utils.writeStr("Is a directory"),
            14 => utils.writeStr("Bad address"),
            else => {
                utils.writeStr("Error ");
                writeNumber(@intCast(-fd));
            },
        }
        utils.writeStr("\n");
        return;
    }

    // Read and display file contents
    var buffer: [256]u8 = undefined;
    while (true) {
        const n = sys.read(@intCast(fd), @ptrCast(&buffer), buffer.len);
        if (n <= 0) break;

        // Write to stdout
        _ = sys.write(1, @ptrCast(&buffer), @intCast(n));
    }

    // Close file
    _ = sys.close(@intCast(fd));
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
