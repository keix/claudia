// Exit command implementation
const write = @import("syscalls/io/write").write;

const STDOUT: usize = 1;

fn write_str(str: []const u8) void {
    _ = write(STDOUT, @ptrCast(str.ptr), str.len);
}

pub fn main(args: []const u8) void {
    _ = args;
    
    write_str("Exiting shell...\n");
    // Note: Actual exit is handled by the shell main loop
}