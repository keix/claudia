// Simple filesystem for RAM disk
// Very basic implementation with fixed-size file table
const std = @import("std");
const blockdev = @import("../driver/blockdev.zig");

// Filesystem constants
const MAGIC: u32 = 0x53494D50; // 'SIMP'
const MAX_FILES: u32 = 8; // Reduced to fit in one block
const MAX_FILENAME: u32 = 28;
const DATA_START_BLOCK: u32 = 2; // After superblock and file table

// On-disk structures
pub const SuperBlock = extern struct {
    magic: u32,
    total_blocks: u32,
    free_blocks: u32,
    file_count: u32,
    reserved: [496]u8 = undefined, // Pad to 512 bytes
};

pub const FileEntry = extern struct {
    name: [MAX_FILENAME]u8, // 28 bytes
    size: u32, // 4 bytes
    start_block: u32, // 4 bytes
    blocks_used: u32, // 4 bytes
    flags: u32, // 4 bytes
    reserved: [20]u8 = undefined, // Pad to 64 bytes (28+4+4+4+4+20=64)
};

comptime {
    if (@sizeOf(SuperBlock) != 512) @compileError("SuperBlock must be 512 bytes");
    if (@sizeOf(FileEntry) != 64) @compileError("FileEntry must be 64 bytes");
}

// Global storage for SimpleFS to avoid stack issues
var global_fs: SimpleFS = undefined;

// In-memory filesystem state
pub const SimpleFS = struct {
    device: *blockdev.BlockDevice,
    super: SuperBlock,
    files: [MAX_FILES]FileEntry,

    pub fn format(device: *blockdev.BlockDevice) !void {
        // Create superblock
        var super = SuperBlock{
            .magic = MAGIC,
            .total_blocks = @intCast(device.total_blocks),
            .free_blocks = @intCast(device.total_blocks - DATA_START_BLOCK),
            .file_count = 0,
        };

        // Write superblock
        const super_bytes = std.mem.asBytes(&super);
        var block_buf: [blockdev.BLOCK_SIZE]u8 = undefined;
        @memcpy(block_buf[0..@sizeOf(SuperBlock)], super_bytes);
        try device.writeBlock(0, &block_buf);

        // Clear file table (only block 1 for 16 files)
        @memset(&block_buf, 0);
        try device.writeBlock(1, &block_buf);
    }

    pub fn mount(device: *blockdev.BlockDevice) error{InvalidFilesystem}!*SimpleFS {
        // Initialize global_fs first with minimal data
        global_fs.device = device;
        @memset(std.mem.asBytes(&global_fs.files), 0);

        // Read superblock
        var block_buf: [blockdev.BLOCK_SIZE]u8 = undefined;
        device.readBlock(0, &block_buf) catch {
            return error.InvalidFilesystem;
        };

        // Copy superblock
        global_fs.super = std.mem.bytesToValue(SuperBlock, block_buf[0..@sizeOf(SuperBlock)]);

        if (global_fs.super.magic != MAGIC) {
            return error.InvalidFilesystem;
        }

        // Read file table from block 1
        device.readBlock(1, &block_buf) catch {
            return error.InvalidFilesystem;
        };

        // Load file entries (up to 8 entries per block)
        const entries_per_block = blockdev.BLOCK_SIZE / @sizeOf(FileEntry);
        var i: usize = 0;
        while (i < entries_per_block and i < MAX_FILES) : (i += 1) {
            const offset = i * @sizeOf(FileEntry);
            global_fs.files[i] = std.mem.bytesToValue(FileEntry, block_buf[offset .. offset + @sizeOf(FileEntry)]);
        }

        return &global_fs;
    }

    pub fn createFile(self: *SimpleFS, name: []const u8, content: []const u8) !void {
        if (name.len >= MAX_FILENAME) return error.NameTooLong;

        // First, check if file already exists and update it
        for (&self.files) |*entry| {
            if (entry.flags == 1) {
                const entry_name = std.mem.sliceTo(&entry.name, 0);
                if (std.mem.eql(u8, entry_name, name)) {
                    // File exists, update it
                    // Free old blocks if size is different
                    const old_blocks = entry.blocks_used;
                    const new_blocks = if (content.len == 0) 0 else (content.len + blockdev.BLOCK_SIZE - 1) / blockdev.BLOCK_SIZE;

                    if (new_blocks > self.super.free_blocks + old_blocks) return error.NoSpace;

                    // Write new content

                    var block_buf: [blockdev.BLOCK_SIZE]u8 = undefined;
                    var written: usize = 0;
                    if (new_blocks > 0) {
                        for (0..new_blocks) |i| {
                            @memset(&block_buf, 0);
                            const to_write = @min(blockdev.BLOCK_SIZE, content.len - written);
                            @memcpy(block_buf[0..to_write], content[written .. written + to_write]);

                            const block_num = entry.start_block + i;
                            try self.device.writeBlock(block_num, &block_buf);
                            written += to_write;
                        }
                    }

                    // Update entry
                    entry.size = @intCast(content.len);
                    entry.blocks_used = @intCast(new_blocks);

                    // Update superblock
                    self.super.free_blocks = self.super.free_blocks + @as(u32, @intCast(old_blocks)) - @as(u32, @intCast(new_blocks));

                    try self.sync();
                    return;
                }
            }
        }

        // File doesn't exist, find free entry
        var free_entry: ?*FileEntry = null;
        for (&self.files) |*entry| {
            if (entry.flags == 0) {
                free_entry = entry;
                break;
            }
        }

        const entry = free_entry orelse return error.NoSpace;

        // Calculate blocks needed
        const blocks_needed = if (content.len == 0) 0 else (content.len + blockdev.BLOCK_SIZE - 1) / blockdev.BLOCK_SIZE;
        if (blocks_needed > self.super.free_blocks) return error.NoSpace;

        // Find contiguous free blocks
        // Calculate the next free block based on existing files
        var next_free_block: u32 = DATA_START_BLOCK;
        for (&self.files) |*existing_entry| {
            if (existing_entry.flags == 1) {
                const end_block = existing_entry.start_block + existing_entry.blocks_used;
                if (end_block > next_free_block) {
                    next_free_block = end_block;
                }
            }
        }
        const start_block = next_free_block;

        // Write file data
        var block_buf: [blockdev.BLOCK_SIZE]u8 = undefined;
        var written: usize = 0;
        if (blocks_needed > 0) {
            for (0..blocks_needed) |i| {
                @memset(&block_buf, 0);
                const to_write = @min(blockdev.BLOCK_SIZE, content.len - written);
                @memcpy(block_buf[0..to_write], content[written .. written + to_write]);

                const block_num = start_block + i;
                try self.device.writeBlock(block_num, &block_buf);
                written += to_write;
            }
        }

        // Update file entry
        @memset(&entry.name, 0);
        @memcpy(entry.name[0..name.len], name);
        entry.size = @intCast(content.len);
        entry.start_block = @intCast(start_block);
        entry.blocks_used = @intCast(blocks_needed);
        entry.flags = 1;

        // Update superblock
        self.super.file_count += 1;
        self.super.free_blocks -= @intCast(blocks_needed);

        // Write updated structures
        try self.sync();
    }

    pub fn readFile(self: *SimpleFS, name: []const u8, buffer: []u8) !usize {
        // Find file
        var file_entry: ?*const FileEntry = null;
        for (&self.files) |*entry| {
            if (entry.flags == 1) {
                const entry_name = std.mem.sliceTo(&entry.name, 0);
                if (std.mem.eql(u8, entry_name, name)) {
                    file_entry = entry;
                    break;
                }
            }
        }

        const entry = file_entry orelse return error.FileNotFound;

        if (buffer.len < entry.size) return error.BufferTooSmall;

        // Read file data
        var block_buf: [blockdev.BLOCK_SIZE]u8 = undefined;
        var read: usize = 0;
        for (0..entry.blocks_used) |i| {
            try self.device.readBlock(entry.start_block + i, &block_buf);
            const to_read = @min(blockdev.BLOCK_SIZE, entry.size - read);
            @memcpy(buffer[read .. read + to_read], block_buf[0..to_read]);
            read += to_read;
        }

        return entry.size;
    }

    pub fn listFiles(self: *SimpleFS) void {
        const uart = @import("../driver/uart/core.zig");
        uart.puts("Files in SimpleFS:\n");

        // Limit to MAX_FILES to prevent infinite loops
        var count: usize = 0;
        for (&self.files) |*entry| {
            if (count >= MAX_FILES) break;
            count += 1;

            if (entry.flags == 1) {
                // Safe name extraction - create a null-terminated buffer
                var name_buf: [MAX_FILENAME + 1]u8 = undefined;
                var name_len: usize = 0;
                while (name_len < MAX_FILENAME and entry.name[name_len] != 0) : (name_len += 1) {
                    name_buf[name_len] = entry.name[name_len];
                }
                name_buf[name_len] = 0; // Null terminate

                if (name_len > 0) {
                    uart.puts("  ");
                    // Print only the actual filename without garbage
                    for (0..name_len) |j| {
                        uart.putc(name_buf[j]);
                    }
                    // Add spacing for alignment
                    var padding: usize = if (name_len < 20) 20 - name_len else 0;
                    while (padding > 0) : (padding -= 1) {
                        uart.putc(' ');
                    }
                    uart.puts(" (");
                    uart.putDec(entry.size);
                    uart.puts(" bytes)\n");
                }
            }
        }
    }

    fn sync(self: *SimpleFS) !void {
        // Write superblock
        const super_bytes = std.mem.asBytes(&self.super);
        var block_buf: [blockdev.BLOCK_SIZE]u8 = undefined;
        @memset(&block_buf, 0);
        @memcpy(block_buf[0..@sizeOf(SuperBlock)], super_bytes);
        try self.device.writeBlock(0, &block_buf);

        // Write file table
        var current_block_num: u64 = 999999; // Invalid block number to force initial read
        for (0..MAX_FILES) |i| {
            const block_num = 1 + (i * @sizeOf(FileEntry)) / blockdev.BLOCK_SIZE;
            const offset = (i * @sizeOf(FileEntry)) % blockdev.BLOCK_SIZE;

            // Read block if it's a different block than the current one
            if (block_num != current_block_num) {
                // Write previous block if needed
                if (current_block_num != 999999) {
                    try self.device.writeBlock(current_block_num, &block_buf);
                }

                // Read new block
                @memset(&block_buf, 0);
                if (offset != 0) {
                    // Partial block - need to preserve existing data
                    try self.device.readBlock(block_num, &block_buf);
                }
                current_block_num = block_num;
            }

            const entry_bytes = std.mem.asBytes(&self.files[i]);
            @memcpy(block_buf[offset .. offset + @sizeOf(FileEntry)], entry_bytes);
        }

        // Write the last block
        if (current_block_num != 999999) {
            try self.device.writeBlock(current_block_num, &block_buf);
        }
    }
};
