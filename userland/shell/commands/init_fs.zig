// init_fs - Initialize/format SimpleFS on RAM disk
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    utils.writeStr("Formatting SimpleFS on RAM disk...\n");
    
    // Open /dev/ramdisk
    const path = "/dev/ramdisk";
    const fd = sys.open(@ptrCast(path.ptr), sys.abi.O_RDWR, 0);
    if (fd < 0) {
        utils.writeStr("Error: Cannot open /dev/ramdisk\n");
        return;
    }
    defer _ = sys.close(@intCast(fd));
    
    // Send format command (0x00 = format)
    var cmd_buffer: [1]u8 = .{0x00};
    const written = sys.write(@intCast(fd), @ptrCast(&cmd_buffer), 1);
    if (written != 1) {
        utils.writeStr("Error: Failed to send format command\n");
        return;
    }
    
    utils.writeStr("SimpleFS formatted successfully!\n");
}
