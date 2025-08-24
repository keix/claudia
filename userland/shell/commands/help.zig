// Help command implementation
const sys = @import("sys");
const utils = @import("shell/utils");

const STDOUT: usize = 1;

fn write_str(str: []const u8) void {
    _ = sys.write(STDOUT, @ptrCast(str.ptr), str.len);
}

pub fn main(args: *const utils.Args) void {
    _ = args;

    write_str("Available commands:\n");
    write_str("  echo  - Echo arguments to stdout\n");
    write_str("  help  - Show this help\n");
    write_str("  exit  - Exit the shell\n");
}
