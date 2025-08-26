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
    if (args.len < 3) {
        utils.writeStr("Usage: write_fs <filename> <content>\n");
        return;
    }

    const filename = args[1];
    const content = args[2];

    // Open /dev/ramdisk for writing
    const path = "/dev/ramdisk";
    const fd = sys.open(@ptrCast(path.ptr), sys.abi.O_RDWR, 0);
    if (fd < 0) {
        utils.writeStr("Error: Cannot open /dev/ramdisk\n");
        return;
    }
    defer _ = sys.close(@intCast(fd));

    // Create the file in SimpleFS
    // Format: Command byte (0x01 = create file), filename length, filename, content length, content
    var buffer: [1024]u8 = undefined;
    var pos: usize = 0;

    // Command: Create file
    buffer[pos] = 0x01;
    pos += 1;

    // Filename length and filename
    buffer[pos] = @intCast(filename.len);
    pos += 1;
    @memcpy(buffer[pos .. pos + filename.len], filename);
    pos += filename.len;

    // Content length (4 bytes, little endian)
    const content_len = @as(u32, @intCast(content.len));
    buffer[pos] = @intCast(content_len & 0xFF);
    buffer[pos + 1] = @intCast((content_len >> 8) & 0xFF);
    buffer[pos + 2] = @intCast((content_len >> 16) & 0xFF);
    buffer[pos + 3] = @intCast((content_len >> 24) & 0xFF);
    pos += 4;

    // Content
    @memcpy(buffer[pos .. pos + content.len], content);
    pos += content.len;

    // Write to ramdisk
    const written = sys.write(@intCast(fd), @ptrCast(&buffer), pos);
    if (written < 0 or written != @as(isize, @intCast(pos))) {
        utils.writeStr("Error: Failed to write complete data\n");
        return;
    }

    utils.writeStr("File '");
    utils.writeStr(filename);
    utils.writeStr("' written to SimpleFS (");
    utils.writeStr(utils.intToStr(@intCast(content.len)));
    utils.writeStr(" bytes)\n");
}

pub fn help() !void {
    utils.writeStr("write_fs - Write a file to SimpleFS\n");
    utils.writeStr("Usage: write_fs <filename> <content>\n");
    utils.writeStr("Example: write_fs hello.lisp \"(print \\\"Hello from Lisp!\\\")\"\n");
}
