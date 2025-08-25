// Tool to create initrd image from host files
const std = @import("std");

// SimpleFS constants (must match kernel/fs/simplefs.zig)
const MAGIC: u32 = 0x53494D50; // 'SIMP'
const MAX_FILES: u32 = 8;
const MAX_FILENAME: u32 = 28;
const BLOCK_SIZE: u32 = 512;
const DATA_START_BLOCK: u32 = 2;

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <output.img> <file1> [file2] ...\n", .{args[0]});
        std.debug.print("Creates a SimpleFS initrd image containing the specified files\n", .{});
        return;
    }

    const output_path = args[1];
    const input_files = args[2..];

    // Calculate total size needed
    var total_blocks: u32 = DATA_START_BLOCK;
    var file_infos = try allocator.alloc(FileInfo, input_files.len);
    defer allocator.free(file_infos);

    // Read all input files
    for (input_files, 0..) |path, i| {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        const size = stat.size;
        const blocks_needed = if (size == 0) 0 else @as(u32, @intCast((size + BLOCK_SIZE - 1) / BLOCK_SIZE));

        file_infos[i] = .{
            .path = path,
            .size = @intCast(size),
            .blocks_needed = blocks_needed,
            .start_block = total_blocks,
        };

        total_blocks += blocks_needed;
    }

    // Create output file
    const out_file = try std.fs.cwd().createFile(output_path, .{});
    defer out_file.close();

    // Create and write superblock
    var super = SuperBlock{
        .magic = MAGIC,
        .total_blocks = total_blocks,
        .free_blocks = 0,
        .file_count = @intCast(input_files.len),
    };

    var block_buf: [BLOCK_SIZE]u8 = undefined;
    @memset(&block_buf, 0);
    @memcpy(block_buf[0..@sizeOf(SuperBlock)], std.mem.asBytes(&super));
    try out_file.writeAll(&block_buf);

    // Create and write file table
    @memset(&block_buf, 0);
    for (file_infos, 0..) |info, i| {
        var entry = FileEntry{
            .name = undefined,
            .size = info.size,
            .start_block = info.start_block,
            .blocks_used = info.blocks_needed,
            .flags = 1,
            .reserved = undefined,
        };

        // Extract filename from path
        const basename = std.fs.path.basename(info.path);
        if (basename.len >= MAX_FILENAME) {
            std.debug.print("Warning: filename '{s}' truncated\n", .{basename});
        }

        @memset(&entry.name, 0);
        const copy_len = @min(basename.len, MAX_FILENAME - 1);
        @memcpy(entry.name[0..copy_len], basename[0..copy_len]);

        const offset = i * @sizeOf(FileEntry);
        @memcpy(block_buf[offset..offset + @sizeOf(FileEntry)], std.mem.asBytes(&entry));
    }
    try out_file.writeAll(&block_buf);

    // Write file data
    for (file_infos) |info| {
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

    std.debug.print("Created initrd image: {s}\n", .{output_path});
    std.debug.print("  Total size: {} bytes ({} blocks)\n", .{ total_blocks * BLOCK_SIZE, total_blocks });
    std.debug.print("  Files: {}\n", .{input_files.len});
    for (file_infos) |info| {
        const basename = std.fs.path.basename(info.path);
        std.debug.print("    {s}: {} bytes\n", .{ basename, info.size });
    }
}

const FileInfo = struct {
    path: []const u8,
    size: u32,
    blocks_needed: u32,
    start_block: u32,
};