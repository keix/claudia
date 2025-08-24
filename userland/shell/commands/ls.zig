// ls - List directory contents
// Skeleton implementation for when filesystem is ready

const sys = @import("sys");
const utils = @import("shell/utils");

// Directory entry structure (matches what kernel will provide)
const DirEntry = struct {
    name: [256]u8,
    name_len: u8,
    type: FileType,
    size: u64,
};

const FileType = enum(u8) {
    regular = 1,
    directory = 2,
    device = 3,
    _,
};

pub fn main(args: *const utils.Args) void {
    // Default to current directory if no argument
    const path = if (args.argc > 1) args.argv[1] else ".";

    // For now, just print a mock directory listing
    // When filesystem is implemented, this will use real open/read syscalls
    mockListing(path) catch |err| {
        _ = err;
        utils.writeStr("ls: error listing directory\n");
    };
}

// Temporary mock implementation until filesystem is ready
fn mockListing(path: []const u8) !void {
    utils.writeStr("ls: ");
    utils.writeStr(path);
    utils.writeStr("\n");

    // Mock entries for demonstration
    const mock_entries = [_]struct { name: []const u8, type: []const u8 }{
        .{ .name = ".", .type = "dir" },
        .{ .name = "..", .type = "dir" },
        .{ .name = "bin", .type = "dir" },
        .{ .name = "dev", .type = "dir" },
        .{ .name = "etc", .type = "dir" },
        .{ .name = "init", .type = "file" },
        .{ .name = "shell", .type = "file" },
    };

    for (mock_entries) |entry| {
        utils.writeStr(entry.name);
        if (utils.strEq(entry.type, "dir")) {
            utils.writeStr("/");
        }
        utils.writeStr("\n");
    }
}

// Future implementation when filesystem is ready
fn realListing(path: []const u8) !void {
    // Open directory
    const dir_fd = try sys.open(path, .{ .directory = true });
    defer _ = sys.close(dir_fd) catch {};

    var buf: [1024]u8 = undefined;

    while (true) {
        // Read directory entries
        const n = try sys.read(dir_fd, &buf);
        if (n == 0) break;

        // Parse entries from buffer
        var offset: usize = 0;
        while (offset < n) {
            const entry = parseDirEntry(buf[offset..n]);
            if (entry) |e| {
                // Print entry name
                utils.writeStr(e.name[0..e.name_len]);

                // Add type indicator
                switch (e.type) {
                    .directory => utils.writeStr("/"),
                    .device => utils.writeStr("*"),
                    else => {},
                }
                utils.writeStr("\n");

                offset += e.entry_size;
            } else {
                break;
            }
        }
    }
}

// Parse directory entry from buffer
fn parseDirEntry(buf: []const u8) ?struct { name: []const u8, name_len: usize, type: FileType, entry_size: usize } {
    if (buf.len < @sizeOf(DirEntry)) return null;

    // In a real implementation, this would decode the kernel's directory entry format
    // For now, return null since we don't have a filesystem
    return null;
}
