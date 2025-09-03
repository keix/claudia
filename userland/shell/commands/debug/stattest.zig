// Test stat system call
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    if (args.len < 2) {
        utils.writeStr("Usage: stattest <file>\n");
        return;
    }

    const path = args.get(1);
    utils.writeStr("Getting status of: ");
    utils.writeStr(path);
    utils.writeStr("\n");

    var stat_buf: sys.abi.Stat = undefined;

    // Null-terminate the path
    var path_buf: [256]u8 = undefined;
    var i: usize = 0;
    while (i < path.len and i < 255) : (i += 1) {
        path_buf[i] = path[i];
    }
    path_buf[i] = 0;

    sys.stat(&path_buf[0], &stat_buf) catch |err| {
        utils.writeStr("stat failed: ");
        utils.writeStr(@errorName(err));
        utils.writeStr("\n");
        return;
    };

    utils.writeStr("\nFile information:\n");

    // File type
    utils.writeStr("  Type: ");
    const mode = stat_buf.st_mode;
    if ((mode & sys.abi.S_IFMT) == sys.abi.S_IFREG) {
        utils.writeStr("regular file");
    } else if ((mode & sys.abi.S_IFMT) == sys.abi.S_IFDIR) {
        utils.writeStr("directory");
    } else if ((mode & sys.abi.S_IFMT) == sys.abi.S_IFCHR) {
        utils.writeStr("character device");
    } else if ((mode & sys.abi.S_IFMT) == sys.abi.S_IFIFO) {
        utils.writeStr("FIFO/pipe");
    } else {
        utils.writeStr("unknown");
    }
    utils.writeStr("\n");

    // Size
    utils.writeStr("  Size: ");
    utils.writeStr(utils.intToStr(@intCast(stat_buf.st_size)));
    utils.writeStr(" bytes\n");

    // Permissions
    utils.writeStr("  Mode: ");
    utils.writeOctal(@intCast(mode & 0o777));
    utils.writeStr("\n");

    // Inode
    utils.writeStr("  Inode: ");
    utils.writeStr(utils.intToStr(@intCast(stat_buf.st_ino)));
    utils.writeStr("\n");

    // Blocks
    utils.writeStr("  Blocks: ");
    utils.writeStr(utils.intToStr(@intCast(stat_buf.st_blocks)));
    utils.writeStr("\n");

    // Times
    utils.writeStr("  Access time: ");
    utils.writeStr(utils.intToStr(@intCast(stat_buf.st_atime)));
    utils.writeStr("\n");
    utils.writeStr("  Modify time: ");
    utils.writeStr(utils.intToStr(@intCast(stat_buf.st_mtime)));
    utils.writeStr("\n");
}

fn writeOctal(value: u32) void {
    var buf: [12]u8 = undefined;
    var i: usize = 11;
    var v = value;

    buf[i] = 0;
    i -= 1;

    if (v == 0) {
        buf[i] = '0';
        utils.writeStr(buf[i..]);
        return;
    }

    while (v > 0 and i > 0) {
        buf[i] = '0' + @as(u8, @intCast(v & 7));
        v >>= 3;
        i -= 1;
    }

    utils.writeStr(buf[i + 1 ..]);
}
