// rm command - remove files or directories
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    if (args.argc < 2) {
        utils.writeStr("Usage: rm <file>...\n");
        return;
    }

    var i: usize = 1;
    while (i < args.argc) : (i += 1) {
        const path = args.argv[i];

        // Convert to null-terminated string
        var path_buf: [256]u8 = undefined;
        utils.strCopy(&path_buf, path);

        const result = sys.unlink(@ptrCast(&path_buf));
        if (result < 0) {
            utils.writeStr("rm: cannot remove '");
            utils.writeStr(path);
            utils.writeStr("': ");

            // Print error message based on error code
            const err = -result;
            if (err == sys.abi.ENOENT) {
                utils.writeStr("No such file or directory");
            } else if (err == sys.abi.EBUSY) {
                utils.writeStr("Resource busy or directory not empty");
            } else if (err == sys.abi.ENOTDIR) {
                utils.writeStr("Not a directory");
            } else {
                utils.writeStr("Error ");
                utils.writeDec(@as(u64, @intCast(err)));
            }
            utils.writeStr("\n");
        }
    }
}
