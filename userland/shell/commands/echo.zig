// Echo command implementation
const sys = @import("sys");
const utils = @import("shell/utils");

const STDOUT: usize = 1;

fn write_str(str: []const u8) void {
    _ = sys.write(STDOUT, @ptrCast(str.ptr), str.len);
}

// Echo command entry point
pub fn main(args: *const utils.Args) void {
    // Echo all arguments after the command name
    if (args.argc <= 1) {
        // No arguments, just print newline
        write_str("\n");
        return;
    }

    // Print arguments separated by spaces
    var i: usize = 1;
    while (i < args.argc) : (i += 1) {
        write_str(args.argv[i]);
        if (i < args.argc - 1) {
            write_str(" ");
        }
    }
    write_str("\n");
}
