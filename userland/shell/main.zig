// Main shell implementation
const syscall = @import("syscall");
const sysno = @import("sysno");
const commands = @import("shell/commands/index");

const STDIN: usize = 0;
const STDOUT: usize = 1;

pub fn write_str(str: []const u8) void {
    _ = syscall.syscall3(sysno.sys_write, STDOUT, @intFromPtr(str.ptr), str.len);
}

fn read_char(buf: *u8) isize {
    return syscall.syscall3(sysno.sys_read, STDIN, @intFromPtr(buf), 1);
}

// Assembly function to execute WFI (Wait For Interrupt)
fn wait_for_interrupt() void {
    asm volatile ("wfi");
}

pub fn main() noreturn {
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
            if (result <= 0) {
                // No input available, wait for interrupt to wake us up
                wait_for_interrupt();
                continue;
            }

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

        // Dispatch commands using index
        var found = false;
        for (commands.commands) |cmd| {
            if (str_eq(trimmed_cmd, cmd.name)) {
                cmd.func(trimmed_cmd); // TODO: Pass actual arguments in the future
                found = true;
                
                // Special handling for exit
                if (str_eq(cmd.name, "exit")) {
                    running = false;
                }
                break;
            }
        }
        
        if (!found and trimmed_cmd.len > 0) {
            write_str("Unknown command: ");
            write_str(trimmed_cmd);
            write_str("\n");
        }
    }

    _ = syscall.syscall3(sysno.sys_exit, 0, 0, 0);

    // Never reached
    while (true) {}
}

pub fn str_eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (ca != cb) return false;
    }
    return true;
}
