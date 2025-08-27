// /sbin/init - System initialization process
const syscall = @import("syscall");
const abi = @import("abi");

const STDOUT: usize = 1;

fn write_str(str: []const u8) void {
    _ = syscall.syscall3(abi.sysno.sys_write, STDOUT, @intFromPtr(str.ptr), str.len);
}

fn showMotd() void {
    write_str("\x1b[2J\x1b[H"); // Clear screen and move cursor to home position

    // Try to read /etc/motd
    const fd = syscall.syscall3(abi.sysno.sys_openat, @as(usize, @bitCast(@as(isize, -100))), @intFromPtr("/etc/motd".ptr), 0);
    if (@as(isize, @bitCast(fd)) >= 0) {
        // Read and display the file
        var buffer: [1024]u8 = undefined;
        const bytes_read = syscall.syscall3(abi.sysno.sys_read, @intCast(fd), @intFromPtr(&buffer), buffer.len);
        if (@as(isize, @bitCast(bytes_read)) > 0) {
            write_str(buffer[0..@intCast(bytes_read)]);
            write_str("\n");
        }
        _ = syscall.syscall1(abi.sysno.sys_close, @intCast(fd));
    } else {
        // If /etc/motd doesn't exist, show a default message
    }
}

fn exec(filename: []const u8) isize {
    return syscall.syscall3(abi.sysno.sys_execve, @intFromPtr(filename.ptr), 0, 0);
}

export fn _start() noreturn {
    // Initialize the system
    showMotd();

    // Try to exec shell
    const shell_name = "shell\x00";
    const result = exec(shell_name[0..5]);

    if (result < 0) {
        write_str("init: failed to exec shell: ");
        // Simple error display
        write_str("Error ");
        if (result == abi.ENOENT) {
            write_str("ENOENT");
        } else {
            write_str("Unknown");
        }
        write_str("\n");
    }

    // Should not reach here if exec succeeds
    write_str("exec returned unexpectedly\n");
    _ = syscall.syscall1(abi.sysno.sys_exit, 1);

    while (true) {}
}
