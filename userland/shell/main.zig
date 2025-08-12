// Main shell implementation
const sys = @import("sys");
const commands = @import("shell/commands/index");

const STDIN: usize = 0;
const STDOUT: usize = 1;

pub fn write_str(str: []const u8) void {
    _ = sys.write(STDOUT, @ptrCast(str.ptr), str.len);
}

fn read_char(buf: *u8) isize {
    return sys.read(STDIN, @ptrCast(buf), 1);
}

// Assembly function to execute WFI (Wait For Interrupt)
// Note: WFI is a privileged instruction, so we can't use it in user mode
// Instead, we'll just continue the loop and let the syscall block properly
fn wait_for_interrupt() void {
    // In user mode, we can't execute wfi, so just return
    // The blocking read syscall should handle waiting properly
}

pub fn main() noreturn {
    // Simple shell loop
    var buffer: [64]u8 = undefined;

    while (true) {
        // Print prompt
        write_str("claudia:/ # ");

        // Read command line
        var pos: usize = 0;
        while (pos < buffer.len - 1) {
            const result = read_char(&buffer[pos]);
            if (result <= 0) {
                // Read error or no data - the syscall should block properly
                // If it returns immediately, there might be an error
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

                // No special handling needed - exit command calls sys.exit() directly
                break;
            }
        }

        if (!found and trimmed_cmd.len > 0) {
            write_str("Unknown command: ");
            write_str(trimmed_cmd);
            write_str("\n");
        }
    }

    sys.exit(0);

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
