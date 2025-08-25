// list_fs - List files in SimpleFS
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    // Open /dev/ramdisk
    const path = "/dev/ramdisk";
    const fd = sys.open(@ptrCast(path.ptr), sys.abi.O_RDWR, 0);
    if (fd < 0) {
        utils.writeStr("Error: Cannot open /dev/ramdisk\n");
        return;
    }
    defer _ = sys.close(@intCast(fd));

    // Send list files command (0x03 = list files)
    var cmd_buffer: [1]u8 = .{0x03};
    const written = sys.write(@intCast(fd), @ptrCast(&cmd_buffer), 1);
    if (written != 1) {
        utils.writeStr("Error: Failed to send list command\n");
        return;
    }
}