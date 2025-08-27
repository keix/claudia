// pid - Show current process ID
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;
    
    const pid = sys.getpid();
    utils.writeStr("Process ID: ");
    utils.writeStr(utils.intToStr(@intCast(pid)));
    utils.writeStr("\n");
}