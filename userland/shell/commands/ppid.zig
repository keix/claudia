// ppid.zig - Print parent process ID
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    const ppid = sys.getppid();
    utils.writeStr("Parent Process ID: ");
    utils.writeStr(utils.intToStr(@intCast(ppid)));
    utils.writeStr("\n");
}
