// Main shell implementation
const sys = @import("sys");
const commands = @import("shell/commands/index");
const utils = @import("shell/utils");

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
        utils.writeStr("claudia:/ # ");

        // Read command line
        var pos: usize = 0;
        while (pos < buffer.len - 1) {
            const result = utils.readChar(&buffer[pos]);
            if (result <= 0) {
                // Read error or no data - the syscall should block properly
                // If it returns immediately, there might be an error
                continue;
            }

            const ch = buffer[pos];

            // Handle different characters
            if (ch == '\n' or ch == '\r') {
                // End of line - finish input
                utils.writeStr("\n"); // Echo newline
                buffer[pos] = 0; // null terminate
                break;
            } else if (ch >= 32 and ch <= 126) {
                // Printable character - echo it
                const echo_buf = [1]u8{ch};
                utils.writeStr(&echo_buf);
                pos += 1;
            } else {
                // Skip unprintable characters (like stray control chars)
                continue;
            }
        }

        if (pos == 0) continue;

        const trimmed_cmd = utils.parseCommandLine(buffer[0..], pos);

        // Debug output
        utils.writeStr("Command: '");
        utils.writeStr(trimmed_cmd);
        utils.writeStr("' (len=");
        // Simple length display for debugging
        if (trimmed_cmd.len < 10) {
            const len_char = [1]u8{'0' + @as(u8, @intCast(trimmed_cmd.len))};
            utils.writeStr(&len_char);
        } else {
            utils.writeStr("10+");
        }
        utils.writeStr(")\n");

        // Dispatch commands using index
        var found = false;
        for (commands.commands) |cmd| {
            if (utils.strEq(trimmed_cmd, cmd.name)) {
                cmd.func(trimmed_cmd); // TODO: Pass actual arguments in the future
                found = true;

                // No special handling needed - exit command calls sys.exit() directly
                break;
            }
        }

        if (!found and trimmed_cmd.len > 0) {
            utils.writeStr("Unknown command: ");
            utils.writeStr(trimmed_cmd);
            utils.writeStr("\n");
        }
    }

    sys.exit(0);

    // Never reached
    while (true) {}
}
