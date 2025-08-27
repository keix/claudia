// seek - Seek to a position in a file
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    // Usage: seek <filename> <offset> [whence]
    // whence: 0=SEEK_SET (default), 1=SEEK_CUR, 2=SEEK_END
    if (args.argc < 3) {
        utils.writeStr("Usage: seek <filename> <offset> [whence]\n");
        utils.writeStr("  whence: 0=SEEK_SET (default), 1=SEEK_CUR, 2=SEEK_END\n");
        return;
    }

    const filename = args.argv[1];
    const offset_str = args.argv[2];

    // Parse offset
    var offset: i64 = 0;
    var negative = false;
    var i: usize = 0;

    if (offset_str[0] == '-') {
        negative = true;
        i = 1;
    }

    while (i < offset_str.len and offset_str[i] != 0) : (i += 1) {
        if (offset_str[i] < '0' or offset_str[i] > '9') {
            utils.writeStr("seek: invalid offset\n");
            return;
        }
        offset = offset * 10 + (offset_str[i] - '0');
    }

    if (negative) {
        offset = -offset;
    }

    // Parse whence (optional, default to SEEK_SET)
    var whence: i32 = 0; // SEEK_SET
    if (args.argc > 3) {
        if (args.argv[3].len == 1 and args.argv[3][0] >= '0' and args.argv[3][0] <= '2') {
            whence = @intCast(args.argv[3][0] - '0');
        } else {
            utils.writeStr("seek: invalid whence (must be 0, 1, or 2)\n");
            return;
        }
    }

    // Create null-terminated filename
    var filename_buf: [256]u8 = undefined;
    if (filename.len >= filename_buf.len) {
        utils.writeStr("seek: filename too long\n");
        return;
    }
    @memcpy(filename_buf[0..filename.len], filename);
    filename_buf[filename.len] = 0;
    
    // Open file
    const fd = sys.open(@ptrCast(&filename_buf), sys.abi.O_RDWR, 0);
    if (fd < 0) {
        utils.writeStr("seek: ");
        utils.writeStr(filename);
        utils.writeStr(": cannot open\n");
        return;
    }

    // Perform seek
    const new_pos = sys.lseek(@intCast(fd), offset, whence) catch {
        utils.writeStr("seek: lseek failed\n");
        _ = sys.close(@intCast(fd));
        return;
    };

    // Report new position
    utils.writeStr("New position: ");
    utils.writeStr(utils.intToStr(@intCast(new_pos)));
    utils.writeStr("\n");

    // Close file
    _ = sys.close(@intCast(fd));
}
