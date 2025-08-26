const std = @import("std");
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    execute(&args.argv) catch |err| {
        utils.writeStr("Error: ");
        utils.writeStr(@errorName(err));
        utils.writeStr("\n");
    };
}

pub fn execute(args: []const []const u8) !void {
    if (args.len < 2) {
        utils.writeStr("Usage: read_fs <filename>\n");
        return;
    }

    const filename = args[1];

    // Open /dev/ramdisk for reading
    const path = "/dev/ramdisk";
    const fd = sys.open(@ptrCast(path.ptr), sys.abi.O_RDWR, 0);
    if (fd < 0) {
        utils.writeStr("Error: Cannot open /dev/ramdisk\n");
        return;
    }
    defer _ = sys.close(@intCast(fd));

    // Send read file command
    var cmd_buffer: [256]u8 = undefined;
    var pos: usize = 0;

    // Command: Read file (0x02)
    cmd_buffer[pos] = 0x02;
    pos += 1;

    // Filename length and filename
    cmd_buffer[pos] = @intCast(filename.len);
    pos += 1;
    @memcpy(cmd_buffer[pos .. pos + filename.len], filename);
    pos += filename.len;

    // Send command to prepare file read
    const result = sys.write(@intCast(fd), @ptrCast(&cmd_buffer), pos);
    if (result < 0) {
        if (result == -2) { // ENOENT
            utils.writeStr("Error: File '");
            utils.writeStr(filename);
            utils.writeStr("' not found\n");
        } else {
            utils.writeStr("Error: Failed to send read command (");
            utils.writeStr(utils.intToStr(@intCast(-result)));
            utils.writeStr(")\n");
        }
        return;
    } else if (result != @as(isize, @intCast(pos))) {
        utils.writeStr("Error: Incomplete write\n");
        return;
    }

    // Now read the actual file content
    var file_buffer: [4096]u8 = undefined;
    const bytes_read = sys.read(@intCast(fd), @ptrCast(&file_buffer), file_buffer.len);

    if (bytes_read < 0) {
        utils.writeStr("Error: Failed to read file\n");
        return;
    }

    if (bytes_read == 0) {
        utils.writeStr("Error: File not found or empty\n");
        return;
    }

    // Display file content
    _ = sys.write(1, @ptrCast(&file_buffer), @intCast(bytes_read));

    // Ensure we end with a newline if the content doesn't already have one
    if (bytes_read > 0 and file_buffer[@intCast(bytes_read - 1)] != '\n') {
        utils.writeStr("\n");
    }
}

pub fn help() !void {
    utils.writeStr("read_fs - Read a file from SimpleFS\n");
    utils.writeStr("Usage: read_fs <filename>\n");
}
