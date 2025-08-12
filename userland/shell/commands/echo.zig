// Echo command implementation
const write = @import("syscalls/io/write").write;

const STDOUT: usize = 1;

fn write_str(str: []const u8) void {
    _ = write(STDOUT, @ptrCast(str.ptr), str.len);
}

// Echo command entry point
// args: command arguments (for future use)
pub fn main(args: []const u8) void {
    _ = args; // TODO: Parse and echo actual arguments
    
    // For now, just print a simple message
    write_str("Hello from echo command!\n");
}