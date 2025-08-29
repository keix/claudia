// ls - List directory contents (VFS-integrated version)
const sys = @import("sys");
const utils = @import("shell/utils");
const abi = @import("abi");
const syscall = @import("syscall");

// Directory entry structure matching kernel
const DirEntry = extern struct {
    d_ino: u64, // Inode number
    d_off: i64, // Offset to next dirent
    d_reclen: u16, // Length of this record
    d_type: u8, // File type
    d_name: [256]u8, // Filename (null-terminated)
};

// ANSI color codes
const COLOR_RESET = "\x1b[0m";
const COLOR_DIR = "\x1b[34m"; // Blue
const COLOR_EXEC = "\x1b[32m"; // Green
const COLOR_DEVICE = "\x1b[33m"; // Yellow

pub fn main(args: *const utils.Args) void {
    // Check if a path argument was provided
    var target_path: [256]u8 = undefined;
    var path_len: usize = 0;

    if (args.argc > 1) {
        // Use the provided path
        const arg_path = args.argv[1];
        var i: usize = 0;
        while (i < 255 and arg_path[i] != 0) : (i += 1) {
            target_path[i] = arg_path[i];
        }
        target_path[i] = 0;
        path_len = i;
    } else {
        // Use current directory
        target_path[0] = '.';
        target_path[1] = 0;
        path_len = 1;
    }

    // Open the directory
    const AT_FDCWD: isize = -100;
    const fd_result = syscall.syscall4(abi.sysno.sys_openat, @bitCast(@as(isize, AT_FDCWD)), @intFromPtr(&target_path), abi.O_RDONLY | abi.O_DIRECTORY, 0);

    if (fd_result < 0) {
        utils.writeStr("ls: cannot open directory: Error ");
        utils.writeDec(@intCast(-fd_result));
        utils.writeStr("\n");
        return;
    }

    const fd = @as(usize, @intCast(fd_result));

    var buffer: [4096]u8 align(8) = undefined;
    const result = syscall.syscall3(abi.sysno.sys_getdents64, fd, @intFromPtr(&buffer), buffer.len);

    if (result < 0) {
        utils.writeStr("ls: cannot read directory: Error ");
        utils.writeDec(@intCast(-result));
        utils.writeStr("\n");
        return;
    }

    if (result == 0) {
        utils.writeStr("0 items\n");
        return;
    }

    // Parse the buffer and count entries (excluding . and ..)
    var offset: usize = 0;
    const total = @as(usize, @intCast(result));
    var visible_count: usize = 0;

    // First pass: count visible entries
    while (offset < total) {
        const entry = @as(*const DirEntry, @ptrCast(@alignCast(&buffer[offset])));

        // Get name length
        var name_len: usize = 0;
        while (name_len < 256 and entry.d_name[name_len] != 0) : (name_len += 1) {}

        // Skip only .. entry (keep . entry to show current directory)
        if (!(name_len == 2 and entry.d_name[0] == '.' and entry.d_name[1] == '.')) {
            visible_count += 1;
        }

        offset += entry.d_reclen;
    }

    // Display count
    utils.writeDec(visible_count);
    utils.writeStr(" items\n\n");

    // Second pass: display entries
    offset = 0;
    while (offset < total) {
        const entry = @as(*const DirEntry, @ptrCast(@alignCast(&buffer[offset])));

        // Get name
        var name_len: usize = 0;
        while (name_len < 256 and entry.d_name[name_len] != 0) : (name_len += 1) {}
        const name = entry.d_name[0..name_len];

        // Skip only .. entry
        if (name_len == 2 and name[0] == '.' and name[1] == '.') {
            offset += entry.d_reclen;
            continue;
        }

        // File type indicator
        switch (entry.d_type) {
            2 => utils.writeStr("[DIR]  "), // Directory
            3 => utils.writeStr("[DEV]  "), // Device
            else => utils.writeStr("[FILE] "), // Regular file
        }

        // Name with color
        switch (entry.d_type) {
            2 => {
                utils.writeStr(COLOR_DIR);
                utils.writeStr(name);
                utils.writeStr("/");
                utils.writeStr(COLOR_RESET);
            },
            3 => {
                utils.writeStr(COLOR_DEVICE);
                utils.writeStr(name);
                utils.writeStr(COLOR_RESET);
            },
            else => {
                // Check for .lisp extension
                if (name_len >= 5 and utils.strEq(name[name_len - 5 ..], ".lisp")) {
                    utils.writeStr(COLOR_EXEC);
                    utils.writeStr(name);
                    utils.writeStr(COLOR_RESET);
                } else {
                    utils.writeStr(name);
                }
            },
        }

        utils.writeStr("\n");
        offset += entry.d_reclen;
    }

    // Close the directory
    _ = syscall.syscall1(abi.sysno.sys_close, fd);
}
