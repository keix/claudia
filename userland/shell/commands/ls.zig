// ls - List directory contents
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    // Default to current directory if no argument
    const path = if (args.argc > 1) args.argv[1] else "/";

    // Allocate buffer for directory entries
    var entries: [32]sys.DirEntry = undefined;
    
    // Debug: show size info
    utils.writeStr("[ls] sizeof(DirEntry) = ");
    writeNumber(@sizeOf(sys.DirEntry));
    utils.writeStr(", buffer size = ");
    writeNumber(@sizeOf(@TypeOf(entries)));
    utils.writeStr("\n");

    // Debug: show what we're listing
    utils.writeStr("[ls] Listing path: ");
    utils.writeStr(path);
    utils.writeStr("\n");
    
    // Read directory
    const count = sys.readdir(path, &entries);
    utils.writeStr("[ls] readdir returned: ");
    writeNumber(@intCast(count));
    utils.writeStr("\n");
    
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
        
        // Debug: show entry details
        utils.writeStr("[ls] Entry ");
        writeNumber(i);
        utils.writeStr(": name_len=");
        writeNumber(entry.name_len);
        utils.writeStr(", type=");
        writeNumber(entry.node_type);
        utils.writeStr(", name='");
        
        // Print first few bytes of name for debug
        var j: usize = 0;
        while (j < 10 and j < entry.name_len) : (j += 1) {
            var ch: [1]u8 = .{entry.name[j]};
            utils.writeStr(&ch);
        }
        if (entry.name_len > 10) {
            utils.writeStr("...");
        }
        utils.writeStr("'\n");
        
        // Also show hex values of first few bytes to detect corruption
        utils.writeStr("      Hex: ");
        j = 0;
        while (j < 8 and j < entry.name_len) : (j += 1) {
            writeHexByte(entry.name[j]);
            utils.writeStr(" ");
        }
        utils.writeStr("\n");

        // Add prefix for directories
        if (entry.node_type == 2) {
            utils.writeStr("/");
        }

        // Print name
        const name = entry.name[0..entry.name_len];
        utils.writeStr(name);

        // Add suffix based on type
        switch (entry.node_type) {
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

fn writeHexByte(byte: u8) void {
    const hex_chars = "0123456789ABCDEF";
    var ch: [1]u8 = undefined;
    
    ch[0] = hex_chars[(byte >> 4) & 0x0F];
    utils.writeStr(&ch);
    
    ch[0] = hex_chars[byte & 0x0F];
    utils.writeStr(&ch);
}
