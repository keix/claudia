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

        // Read command line (canonical mode - reads complete line)
        const result = utils.readLine(buffer[0..]);
        if (result <= 0) {
            // Read error or EOF
            break;
        }

        const bytes_read = @as(usize, @intCast(result));

        // Remove trailing newline if present
        var pos = bytes_read;
        if (pos > 0 and (buffer[pos - 1] == '\n' or buffer[pos - 1] == '\r')) {
            pos -= 1;
        }

        if (pos == 0) continue;

        // Null terminate for string operations
        if (pos < buffer.len) {
            buffer[pos] = 0;
        }

        const trimmed_cmd = utils.parseCommandLine(buffer[0..], pos);

        // Parse arguments
        var args = utils.Args.init();
        utils.parseArgs(trimmed_cmd, &args);

        if (args.argc == 0) continue; // Empty command

        // Dispatch commands using index
        var found = false;
        for (commands.commands) |cmd| {
            if (utils.strEq(args.argv[0], cmd.name)) {
                cmd.func(&args);
                found = true;

                // No special handling needed - exit command calls sys.exit() directly
                break;
            }
        }

        if (!found) {
            utils.writeStr("Unknown command: ");
            utils.writeStr(args.argv[0]);
            utils.writeStr("\n");
        }
    }

    sys.exit(0);

    // Never reached
    while (true) {}
}
