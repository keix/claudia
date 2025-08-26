// Tool to create initrd image from host files
const std = @import("std");

// SimpleFS constants (must match kernel/fs/simplefs.zig)
const MAGIC: u32 = 0x53494D50; // 'SIMP'
const MAX_FILES: u32 = 32;
const MAX_FILENAME: u32 = 28;
const BLOCK_SIZE: u32 = 512;
const DATA_START_BLOCK: u32 = 5;

// File flags
const FLAG_EXISTS: u32 = 0x01;
const FLAG_DIRECTORY: u32 = 0x02;

// On-disk structures
const SuperBlock = extern struct {
    magic: u32,
    total_blocks: u32,
    free_blocks: u32,
    file_count: u32,
    reserved: [496]u8 = undefined,
};

const FileEntry = extern struct {
    name: [MAX_FILENAME]u8,
    size: u32,
    start_block: u32,
    blocks_used: u32,
    flags: u32,
    reserved: [20]u8 = undefined,
};

const FileInfo = struct {
    path: []const u8,
    name: []const u8,
    size: u32,
    blocks_needed: u32,
    start_block: u32,
    is_directory: bool,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <output.img> <input_dir>\n", .{args[0]});
        std.debug.print("Creates a SimpleFS initrd image from directory contents\n", .{});
        return;
    }

    const output_path = args[1];
    const input_dir = args[2];

    // Collect all files and directories
    var file_list = std.ArrayList(FileInfo).init(allocator);
    defer file_list.deinit();

    var total_blocks: u32 = DATA_START_BLOCK;
    try scanDirectory(allocator, input_dir, "", &file_list, &total_blocks);

    if (file_list.items.len > MAX_FILES) {
        std.debug.print("Error: Too many files ({} > {})\n", .{ file_list.items.len, MAX_FILES });
        return;
    }

    // Create output file
    const out_file = try std.fs.cwd().createFile(output_path, .{});
    defer out_file.close();

    // Create and write superblock
    var super = SuperBlock{
        .magic = MAGIC,
        .total_blocks = total_blocks,
        .free_blocks = 0,
        .file_count = @intCast(file_list.items.len),
    };

    var block_buf: [BLOCK_SIZE]u8 = undefined;
    @memset(&block_buf, 0);
    @memcpy(block_buf[0..@sizeOf(SuperBlock)], std.mem.asBytes(&super));
    try out_file.writeAll(&block_buf);

    // Create and write file table (across blocks 1-2)
    const entries_per_block = BLOCK_SIZE / @sizeOf(FileEntry);
    var current_block: u32 = 1;
    var block_index: usize = 0;

    @memset(&block_buf, 0);
    for (file_list.items) |info| {
        // Check if we need to write current block and move to next
        if (block_index >= entries_per_block) {
            try out_file.writeAll(&block_buf);
            @memset(&block_buf, 0);
            current_block += 1;
            block_index = 0;
        }

        var entry = FileEntry{
            .name = undefined,
            .size = info.size,
            .start_block = info.start_block,
            .blocks_used = info.blocks_needed,
            .flags = if (info.is_directory) (FLAG_EXISTS | FLAG_DIRECTORY) else FLAG_EXISTS,
            .reserved = undefined,
        };

        @memset(&entry.name, 0);
        const copy_len = @min(info.name.len, MAX_FILENAME - 1);
        @memcpy(entry.name[0..copy_len], info.name[0..copy_len]);

        const offset = block_index * @sizeOf(FileEntry);
        @memcpy(block_buf[offset .. offset + @sizeOf(FileEntry)], std.mem.asBytes(&entry));
        block_index += 1;
    }

    // Write the last block
    try out_file.writeAll(&block_buf);

    // Write remaining empty blocks up to DATA_START_BLOCK-1
    while (current_block < DATA_START_BLOCK - 1) : (current_block += 1) {
        @memset(&block_buf, 0);
        try out_file.writeAll(&block_buf);
    }

    // Write file data
    for (file_list.items) |info| {
        if (!info.is_directory and info.size > 0) {
            const file = try std.fs.cwd().openFile(info.path, .{});
            defer file.close();

            var written: usize = 0;
            while (written < info.size) {
                @memset(&block_buf, 0);
                const n = try file.read(&block_buf);
                if (n == 0) break;
                try out_file.writeAll(&block_buf);
                written += BLOCK_SIZE;
            }

            // Pad to block boundary
            const remaining = info.blocks_needed * BLOCK_SIZE - written;
            if (remaining > 0) {
                @memset(&block_buf, 0);
                var i: usize = 0;
                while (i < remaining) : (i += BLOCK_SIZE) {
                    try out_file.writeAll(&block_buf);
                }
            }
        }
    }

    std.debug.print("Created initrd image: {s}\n", .{output_path});
    std.debug.print("  Total size: {} bytes ({} blocks)\n", .{ total_blocks * BLOCK_SIZE, total_blocks });
    std.debug.print("  Entries: {}\n", .{file_list.items.len});
    for (file_list.items) |info| {
        if (info.is_directory) {
            std.debug.print("    {s}/ <DIR>\n", .{info.name});
        } else {
            std.debug.print("    {s}: {} bytes\n", .{ info.name, info.size });
        }
    }
}

fn scanDirectory(allocator: std.mem.Allocator, base_path: []const u8, prefix: []const u8, file_list: *std.ArrayList(FileInfo), total_blocks: *u32) !void {
    var dir = try std.fs.cwd().openDir(base_path, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ base_path, entry.name });
        defer allocator.free(full_path);

        const name = if (prefix.len > 0)
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, entry.name })
        else
            try allocator.dupe(u8, entry.name);
        defer allocator.free(name);

        switch (entry.kind) {
            .directory => {
                // Add directory entry
                try file_list.append(.{
                    .path = try allocator.dupe(u8, full_path),
                    .name = try allocator.dupe(u8, name),
                    .size = 0,
                    .blocks_needed = 0,
                    .start_block = 0,
                    .is_directory = true,
                });

                // Recurse into subdirectory
                try scanDirectory(allocator, full_path, name, file_list, total_blocks);
            },
            .file => {
                const file = try std.fs.cwd().openFile(full_path, .{});
                defer file.close();

                const stat = try file.stat();
                const size = stat.size;
                const blocks_needed = if (size == 0) 0 else @as(u32, @intCast((size + BLOCK_SIZE - 1) / BLOCK_SIZE));

                try file_list.append(.{
                    .path = try allocator.dupe(u8, full_path),
                    .name = try allocator.dupe(u8, name),
                    .size = @intCast(size),
                    .blocks_needed = blocks_needed,
                    .start_block = total_blocks.*,
                    .is_directory = false,
                });

                total_blocks.* += blocks_needed;
            },
            else => {
                // Skip other types (symlinks, etc.)
            },
        }
    }
}
