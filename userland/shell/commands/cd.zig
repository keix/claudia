// cd - Change directory
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    // Default to home directory if no argument
    const path = if (args.argc > 1) args.argv[1] else "/";

    sys.chdir(path) catch {
        utils.writeStr("cd: ");
        utils.writeStr(path);
        utils.writeStr(": No such file or directory\n");
        return;
    };
}
