// Simple filesystem for RAM disk
// Very basic implementation with fixed-size file table
const std = @import("std");
const blockdev = @import("../driver/blockdev.zig");

// Filesystem constants
const MAGIC: u32 = 0x53494D50; // 'SIMP'
const MAX_FILES: u32 = 64;
const MAX_FILENAME: u32 = 28;
const DATA_START_BLOCK: u32 = 2; // After superblock and file table

// On-disk structures
const SuperBlock = packed struct {
    magic: u32,
    total_blocks: u32,
    free_blocks: u32,
    file_count: u32,
    reserved: [500]u8 = undefined, // Pad to 512 bytes
};

const FileEntry = packed struct {
    name: [MAX_FILENAME]u8,
    size: u32,
    start_block: u32,
    blocks_used: u32,
    flags: u32, // 0 = free, 1 = used
    reserved: [12]u8 = undefined, // Pad to 64 bytes
};

comptime {
    if (@sizeOf(SuperBlock) != 512) @compileError("SuperBlock must be 512 bytes");
    if (@sizeOf(FileEntry) != 64) @compileError("FileEntry must be 64 bytes");
}

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

        // Clear file table
        @memset(&block_buf, 0);
        for (0..8) |i| { // 8 blocks for file table (512 entries max)
            try device.writeBlock(1 + i, &block_buf);
        }
    }

    pub fn mount(device: *blockdev.BlockDevice) !SimpleFS {
        var fs = SimpleFS{
            .device = device,
            .super = undefined,
            .files = undefined,
        };

        // Read superblock
        var block_buf: [blockdev.BLOCK_SIZE]u8 = undefined;
        try device.readBlock(0, &block_buf);
        fs.super = std.mem.bytesToValue(SuperBlock, block_buf[0..@sizeOf(SuperBlock)]);

        if (fs.super.magic != MAGIC) {
            return error.InvalidFilesystem;
        }

        // Read file table
        for (0..MAX_FILES) |i| {
            const block_num = 1 + (i * @sizeOf(FileEntry)) / blockdev.BLOCK_SIZE;
            const offset = (i * @sizeOf(FileEntry)) % blockdev.BLOCK_SIZE;

            try device.readBlock(block_num, &block_buf);
            fs.files[i] = std.mem.bytesToValue(FileEntry, block_buf[offset .. offset + @sizeOf(FileEntry)]);
        }

        return fs;
    }

    pub fn createFile(self: *SimpleFS, name: []const u8, content: []const u8) !void {
        if (name.len >= MAX_FILENAME) return error.NameTooLong;

        // Find free file entry
        var free_entry: ?*FileEntry = null;
        for (&self.files) |*entry| {
            if (entry.flags == 0) {
                free_entry = entry;
                break;
            }
        }

        const entry = free_entry orelse return error.NoSpace;

        // Calculate blocks needed
        const blocks_needed = (content.len + blockdev.BLOCK_SIZE - 1) / blockdev.BLOCK_SIZE;
        if (blocks_needed > self.super.free_blocks) return error.NoSpace;

        // Find contiguous free blocks
        const start_block = DATA_START_BLOCK + (self.super.total_blocks - self.super.free_blocks - DATA_START_BLOCK);

        // Write file data
        var block_buf: [blockdev.BLOCK_SIZE]u8 = undefined;
        var written: usize = 0;
        for (0..blocks_needed) |i| {
            @memset(&block_buf, 0);
            const to_write = @min(blockdev.BLOCK_SIZE, content.len - written);
            @memcpy(block_buf[0..to_write], content[written .. written + to_write]);
            try self.device.writeBlock(start_block + i, &block_buf);
            written += to_write;
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

        for (&self.files) |*entry| {
            if (entry.flags == 1) {
                const name = std.mem.sliceTo(&entry.name, 0);
                uart.puts("  ");
                uart.puts(name);
                uart.puts(" (");
                uart.putDec(entry.size);
                uart.puts(" bytes)\n");
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
        for (0..MAX_FILES) |i| {
            const block_num = 1 + (i * @sizeOf(FileEntry)) / blockdev.BLOCK_SIZE;
            const offset = (i * @sizeOf(FileEntry)) % blockdev.BLOCK_SIZE;

            // Read block first if we're not at the start
            if (offset != 0 or i == 0) {
                try self.device.readBlock(block_num, &block_buf);
            }

            const entry_bytes = std.mem.asBytes(&self.files[i]);
            @memcpy(block_buf[offset .. offset + @sizeOf(FileEntry)], entry_bytes);

            // Write block if we're at the end or filled it
            if (offset + @sizeOf(FileEntry) == blockdev.BLOCK_SIZE or i == MAX_FILES - 1) {
                try self.device.writeBlock(block_num, &block_buf);
            }
        }
    }
};
