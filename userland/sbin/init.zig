// /sbin/init - System initialization process
const syscall = @import("syscall");
const abi = @import("abi");

const STDOUT: usize = 1;

fn write_str(str: []const u8) void {
    _ = syscall.syscall3(abi.sysno.sys_write, STDOUT, @intFromPtr(str.ptr), str.len);
}

fn fork() isize {
    return syscall.syscall1(abi.sysno.sys_clone, 0); // Simple fork without special flags
}

fn exec(filename: []const u8) isize {
    return syscall.syscall3(abi.sysno.sys_execve, @intFromPtr(filename.ptr), 0, 0);
}

fn motd() void {
    write_str("\x1b[2J\x1b[H"); // Clear screen and move cursor to home position
    write_str("Claudia — A modern rewrite of UNIX Sixth Edition.\n");
    write_str("/* You are *expected* to understand this. */\n");
    write_str("\n");
}

export fn _start() noreturn {
    // Initialize the system
    motd();

    const shell_name = "shell\x00";
    const result = exec(shell_name[0..5]);
    if (result < 0) {
        write_str("Failed to exec shell\n");
        _ = syscall.syscall1(abi.sysno.sys_exit, 1);
    }

    // Should not reach here if exec succeeds
    write_str("exec returned unexpectedly\n");
    _ = syscall.syscall1(abi.sysno.sys_exit, 1);

    // Never reached
    while (true) {}
}

// Helper to print PID (simple decimal output)
fn write_pid(pid: isize) void {
    if (pid == 0) {
        write_str("0");
        return;
    }

    var buffer: [20]u8 = undefined;
    var i: usize = 0;
    var n = @abs(pid);

    // Convert to string
    while (n > 0 and i < buffer.len - 1) {
        buffer[i] = @intCast('0' + (n % 10));
        n /= 10;
        i += 1;
    }

    if (i == 0) {
        buffer[i] = '0';
        i += 1;
    }

    // Reverse the buffer
    var j: usize = 0;
    while (j < i / 2) {
        const tmp = buffer[j];
        buffer[j] = buffer[i - 1 - j];
        buffer[i - 1 - j] = tmp;
        j += 1;
    }

    write_str(buffer[0..i]);
}
