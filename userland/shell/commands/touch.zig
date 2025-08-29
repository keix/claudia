// Touch command - create empty files or update timestamps
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    if (args.argc < 2) {
        utils.writeStr("Usage: touch <file>...\n");
        return;
    }

    // Process each file argument
    var i: usize = 1;
    while (i < args.argc) : (i += 1) {
        const filename = args.argv[i];

        // Try to open file with O_CREAT flag
        // This will create the file if it doesn't exist
        // or just update access time if it does exist
        const fd = sys.open(&filename[0], sys.abi.O_CREAT | sys.abi.O_WRONLY, 0o644);

        if (fd < 0) {
            utils.writeStr("touch: cannot touch '");
            utils.writeStr(filename);
            utils.writeStr("'\n");
            continue;
        }

        // Close the file immediately
        _ = sys.close(@intCast(fd));
    }
}
