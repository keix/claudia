// Help command implementation
const write = @import("syscalls/io/write").write;

const STDOUT: usize = 1;

fn write_str(str: []const u8) void {
    _ = write(STDOUT, @ptrCast(str.ptr), str.len);
}

pub fn main(args: []const u8) void {
    _ = args;
    
    write_str("Available commands:\n");
    write_str("  echo  - Print a message\n");
    write_str("  help  - Show this help\n");
    write_str("  exit  - Exit the shell\n");
}