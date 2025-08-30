// Help command implementation - reads help from /etc/help
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    // Try to open /etc/help
    const help_path = "/etc/help";
    const fd = sys.open(@ptrCast(help_path.ptr), 0, 0);

    if (fd < 0) {
        // Fallback if file doesn't exist
        utils.writeStr("Help file not found at /etc/help\n");
        utils.writeStr("Available commands: cat, cd, date, echo, exit, fstat, help, id, lisp, ls, mkdir, pid, pwd, rm, seek, touch\n");
        return;
    }

    // Read and display the help file
    var buffer: [4096]u8 = undefined;
    while (true) {
        const bytes_read = sys.read(@intCast(fd), &buffer, buffer.len);
        if (bytes_read <= 0) break;

        const data = buffer[0..@intCast(bytes_read)];
        utils.writeStr(data);
    }

    _ = sys.close(@intCast(fd));
}
