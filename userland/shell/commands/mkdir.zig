// userland/shell/commands/mkdir.zig - Create directories
const sys = @import("sys");
const utils = @import("shell/utils");
const defs = @import("abi");
const AT_FDCWD: isize = -100;

pub fn main(args: *const utils.Args) void {
    if (args.argc < 2) {
        utils.writeStr("mkdir: missing operand\n");
        return;
    }

    var i: usize = 1;
    while (i < args.argc) : (i += 1) {
        const path = args.argv[i];

        // Call mkdirat with AT_FDCWD for current directory
        // Mode 0o755 (rwxr-xr-x) is standard for directories
        const result = sys.mkdirat(AT_FDCWD, path, 0o755);

        if (result < 0) {
            utils.writeStr("mkdir: cannot create directory '");
            utils.writeStr(path);
            utils.writeStr("': ");

            // Print error message
            const err = -result;
            if (err == defs.EEXIST) {
                utils.writeStr("File exists");
            } else if (err == defs.EINVAL) {
                utils.writeStr("Invalid argument");
            } else if (err == defs.EFAULT) {
                utils.writeStr("Bad address");
            } else {
                utils.writeStr("Error ");
                utils.writeDec(@intCast(err));
            }
            utils.writeStr("\n");
        }
    }
}
