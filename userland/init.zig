// /init - System initialization and minimal shell
const syscall = @import("syscall");
const sysno = @import("sysno");

const STDIN: usize = 0;
const STDOUT: usize = 1;

fn write_str(str: []const u8) void {
    _ = syscall.syscall3(sysno.sys_write, STDOUT, @intFromPtr(str.ptr), str.len);
}

fn read_char(buf: *u8) isize {
    return syscall.syscall3(sysno.sys_read, STDIN, @intFromPtr(buf), 1);
}

export fn _start() noreturn {
    // MOTD (Message of the Day)
    write_str("\x1b[2J\x1b[H"); // ANSI clear screen
    write_str("Welcome to Claudia!\n");
    write_str("Kernel boot complete. Starting /init shell.\n");
    write_str("Type 'help' for commands, 'exit' to shutdown.\n\n");

    // Simple shell loop
    var buffer: [64]u8 = undefined;
    var running = true;

    while (running) {
        // Print prompt
        write_str("claudia:/ # ");

        // Read command line
        var pos: usize = 0;
        while (pos < buffer.len - 1) {
            const result = read_char(&buffer[pos]);
            if (result <= 0) break;

            const ch = buffer[pos];

            // Handle different characters
            if (ch == '\n' or ch == '\r') {
                // End of line - finish input
                write_str("\n"); // Echo newline
                buffer[pos] = 0; // null terminate
                break;
            } else if (ch >= 32 and ch <= 126) {
                // Printable character - echo it
                const echo_buf = [1]u8{ch};
                write_str(&echo_buf);
                pos += 1;
            } else {
                // Skip unprintable characters (like stray control chars)
                continue;
            }
        }

        if (pos == 0) continue;

        // Process command - skip leading whitespace
        var start: usize = 0;
        while (start < pos and buffer[start] == ' ') start += 1;

        if (start >= pos) continue; // Empty command

        const trimmed_cmd = buffer[start..pos];

        // Command evaluation
        if (str_eq(trimmed_cmd, "help")) {
            write_str("Claudia Shell Commands:\n");
            write_str("  help     - Show this help message\n");
            write_str("  echo     - Display a test message\n");
            write_str("  hello    - Greet the user\n");
            write_str("  version  - Show OS version\n");
            write_str("  uptime   - Show system uptime (stub)\n");
            write_str("  clear    - Clear screen (stub)\n");
            write_str("  exit     - Exit the system\n\n");
        } else if (str_eq(trimmed_cmd, "echo")) {
            write_str("Echo: Hello from Claudia!\n\n");
        } else if (str_eq(trimmed_cmd, "hello")) {
            write_str("Hello! Welcome to Claudia.\n");
            write_str("This is a minimal RISC-V kernel with userland shell.\n\n");
        } else if (str_eq(trimmed_cmd, "version")) {
            write_str("Claudia v0.1.0 - RISC-V 64-bit kernel in Zig\n\n");
        } else if (str_eq(trimmed_cmd, "uptime")) {
            write_str("System uptime: [Not implemented yet]\n\n");
        } else if (str_eq(trimmed_cmd, "clear")) {
            write_str("\x1b[2J\x1b[H"); // ANSI clear screen
            write_str("Screen cleared (if terminal supports ANSI).\n\n");
        } else if (str_eq(trimmed_cmd, "exit")) {
            write_str("Shutting down... Thank you for using Claudia!\n\n");
            running = false;
        } else if (trimmed_cmd.len > 0) {
            write_str("Command not found: '");
            write_str(trimmed_cmd);
            write_str("'\n");
            write_str("Type 'help' to see available commands.\n\n");
        }
    }

    _ = syscall.syscall3(sysno.sys_exit, 0, 0, 0);

    // Never reached
    while (true) {}
}

fn str_eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (ca != cb) return false;
    }
    return true;
}
