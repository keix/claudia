// pwd - Print working directory
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    var buf: [256]u8 = undefined;
    const cwd = sys.getcwd(&buf) catch {
        utils.writeStr("pwd: cannot get current directory\n");
        return;
    };

    utils.writeStr(cwd);
    utils.writeStr("\n");
}
