// Help command implementation
const sys = @import("sys");

const STDOUT: usize = 1;

fn write_str(str: []const u8) void {
    _ = sys.write(STDOUT, @ptrCast(str.ptr), str.len);
}

pub fn main(args: []const u8) void {
    _ = args;

    write_str("Available commands:\n");
    write_str("  echo  - Print a message\n");
    write_str("  help  - Show this help\n");
    write_str("  exit  - Exit the shell\n");
}
