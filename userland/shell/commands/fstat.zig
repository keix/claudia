// fstat - Test fstat system call
const sys = @import("sys");
const utils = @import("shell/utils");
const std = @import("std");

pub fn main(args: *const utils.Args) void {
    if (args.argc < 2) {
        utils.writeStr("Usage: fstat <filename>\n");
        return;
    }

    const filename = args.argv[1];

    // Need to ensure null-termination for the syscall
    var path_buf: [256]u8 = undefined;
    if (filename.len >= path_buf.len) {
        utils.writeStr("fstat: filename too long\n");
        return;
    }
    @memcpy(path_buf[0..filename.len], filename);
    path_buf[filename.len] = 0;

    // Open the file
    const fd = sys.open(@ptrCast(&path_buf), sys.abi.O_RDONLY, 0);
    if (fd < 0) {
        utils.writeStr("fstat: cannot open ");
        utils.writeStr(filename);
        utils.writeStr("\n");
        return;
    }
    defer _ = sys.close(@intCast(fd));

    // Get file status
    var stat: sys.abi.Stat = undefined;
    sys.fstat(@intCast(fd), &stat) catch {
        utils.writeStr("fstat: cannot stat ");
        utils.writeStr(filename);
        utils.writeStr("\n");
        return;
    };

    // Print file information
    utils.writeStr("File: ");
    utils.writeStr(filename);
    utils.writeStr("\n");

    utils.writeStr("Size: ");
    utils.writeDec(@intCast(stat.st_size));
    utils.writeStr(" bytes\n");

    utils.writeStr("Blocks: ");
    utils.writeDec(@intCast(stat.st_blocks));
    utils.writeStr("\n");

    utils.writeStr("Block size: ");
    utils.writeDec(@intCast(stat.st_blksize));
    utils.writeStr("\n");

    utils.writeStr("Inode: ");
    utils.writeDec(@intCast(stat.st_ino));
    utils.writeStr("\n");

    // File type
    utils.writeStr("Type: ");
    if (sys.abi.S_ISREG(stat.st_mode)) {
        utils.writeStr("regular file");
    } else if (sys.abi.S_ISDIR(stat.st_mode)) {
        utils.writeStr("directory");
    } else if (sys.abi.S_ISCHR(stat.st_mode)) {
        utils.writeStr("character device");
    } else if (sys.abi.S_ISBLK(stat.st_mode)) {
        utils.writeStr("block device");
    } else {
        utils.writeStr("unknown");
    }
    utils.writeStr("\n");

    // Permissions
    utils.writeStr("Permissions: ");
    const perms = stat.st_mode & 0o777;
    utils.writeOct(perms);
    utils.writeStr("\n");
}
