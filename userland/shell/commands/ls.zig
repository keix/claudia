// ls - List directory contents
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    // Default to current directory if no argument
    const path = if (args.argc > 1) args.argv[1] else "/";

    utils.writeStr("ls: ");
    utils.writeStr(path);
    utils.writeStr("\n");

    // Allocate buffer for directory entries
    var entries: [32]sys.DirEntry = undefined;

    // Read directory
    const count = sys.readdir(path, &entries);
    if (count < 0) {
        utils.writeStr("ls: cannot access '");
        utils.writeStr(path);
        utils.writeStr("': ");
        switch (-count) {
            2 => utils.writeStr("No such file or directory"),
            20 => utils.writeStr("Not a directory"),
            14 => utils.writeStr("Bad address"),
            else => {
                utils.writeStr("Error ");
                writeNumber(@intCast(-count));
            },
        }
        utils.writeStr("\n");
        return;
    }

    // Display entries
    if (count == 0) {
        utils.writeStr("(empty directory)\n");
        return;
    }

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const entry = &entries[i];

        // Print name
        const name = entry.name[0..entry.name_len];
        utils.writeStr(name);

        // Add suffix based on type
        switch (entry.node_type) {
            2 => utils.writeStr("/"), // Directory
            3 => utils.writeStr("*"), // Device
            else => {}, // Regular file
        }

        utils.writeStr("\n");
    }
}

fn writeNumber(n: usize) void {
    if (n == 0) {
        utils.writeStr("0");
        return;
    }

    var buffer: [20]u8 = undefined;
    var i: usize = 0;
    var num = n;

    while (num > 0 and i < buffer.len) {
        buffer[i] = @intCast('0' + (num % 10));
        num /= 10;
        i += 1;
    }

    while (i > 0) {
        i -= 1;
        var ch: [1]u8 = .{buffer[i]};
        utils.writeStr(&ch);
    }
}
