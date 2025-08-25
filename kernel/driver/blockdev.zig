// Block device interface for Claudia
const std = @import("std");
const file = @import("../file/core.zig");
const vfs = @import("../fs/vfs.zig");

// Block device constants
pub const BLOCK_SIZE: usize = 512; // Standard sector size

// Block device operations interface
pub const BlockDeviceOps = struct {
    read_block: *const fn (dev: *BlockDevice, block_num: u64, buffer: []u8) anyerror!void,
    write_block: *const fn (dev: *BlockDevice, block_num: u64, data: []const u8) anyerror!void,
    get_size: *const fn (dev: *BlockDevice) u64, // Returns size in blocks
};

// Generic block device structure
pub const BlockDevice = struct {
    name: [32]u8,
    name_len: usize,
    ops: *const BlockDeviceOps,
    block_size: usize,
    total_blocks: u64,
    device_data: ?*anyopaque, // Device-specific data

    pub fn init(name: []const u8, ops: *const BlockDeviceOps, total_blocks: u64) BlockDevice {
        var dev = BlockDevice{
            .ops = ops,
            .block_size = BLOCK_SIZE,
            .total_blocks = total_blocks,
            .device_data = null,
            .name_len = @min(name.len, 31),
            .name = undefined,
        };
        @memcpy(dev.name[0..dev.name_len], name[0..dev.name_len]);
        dev.name[dev.name_len] = 0;
        return dev;
    }

    pub fn readBlock(self: *BlockDevice, block_num: u64, buffer: []u8) !void {
        if (buffer.len < self.block_size) return error.BufferTooSmall;
        try self.ops.read_block(self, block_num, buffer);
    }

    pub fn writeBlock(self: *BlockDevice, block_num: u64, data: []const u8) !void {
        if (data.len < self.block_size) return error.BufferTooSmall;
        try self.ops.write_block(self, block_num, data);
    }

    pub fn getSize(self: *BlockDevice) u64 {
        return self.ops.get_size(self);
    }
};

// File operations wrapper for block devices
pub const BlockFileOps = file.types.FileOperations{
    .read = blockRead,
    .write = blockWrite,
    .close = blockClose,
};

var block_file_pos: u64 = 0; // Simple position tracking

fn blockRead(f: *file.types.File, buffer: []u8) isize {
    _ = f;
    _ = buffer;
    // TODO: Implement block-aligned reads
    return 0;
}

fn blockWrite(f: *file.types.File, data: []const u8) isize {
    _ = f;
    _ = data;
    // TODO: Implement block-aligned writes
    return 0;
}

fn blockClose(f: *file.types.File) void {
    _ = f;
    block_file_pos = 0;
}
