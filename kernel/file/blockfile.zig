// Block device file wrapper
const std = @import("std");
const core = @import("core.zig");
const types = @import("types.zig");
const defs = @import("abi");
const blockdev = @import("../driver/blockdev.zig");
const ramdisk = @import("../driver/ramdisk.zig");

// Block device file structure
pub const BlockFile = struct {
    file: core.File,
    device: *blockdev.BlockDevice,
    pos: u64,

    pub fn init(device: *blockdev.BlockDevice) BlockFile {
        return .{
            .file = core.File.init(.DEVICE, &BlockFileOps),
            .device = device,
            .pos = 0,
        };
    }
};

// File operations for block devices
const BlockFileOps = core.FileOperations{
    .read = blockRead,
    .write = blockWrite,
    .close = blockClose,
};

fn blockRead(file: *core.File, buffer: []u8) isize {
    const bf: *BlockFile = @alignCast(@fieldParentPtr("file", file));

    // Calculate block-aligned read
    const block_num = bf.pos / blockdev.BLOCK_SIZE;
    const offset = bf.pos % blockdev.BLOCK_SIZE;

    if (block_num >= bf.device.total_blocks) {
        return 0; // EOF
    }

    // For simplicity, read one block at a time
    var block_buf: [blockdev.BLOCK_SIZE]u8 = undefined;
    bf.device.readBlock(block_num, &block_buf) catch return defs.EIO;

    // Copy data from block buffer
    const available = blockdev.BLOCK_SIZE - offset;
    const to_read = @min(buffer.len, available);
    @memcpy(buffer[0..to_read], block_buf[offset .. offset + to_read]);

    bf.pos += to_read;
    return @as(isize, @intCast(to_read));
}

fn blockWrite(file: *core.File, data: []const u8) isize {
    const bf: *BlockFile = @alignCast(@fieldParentPtr("file", file));

    // Calculate block-aligned write
    const block_num = bf.pos / blockdev.BLOCK_SIZE;
    const offset = bf.pos % blockdev.BLOCK_SIZE;

    if (block_num >= bf.device.total_blocks) {
        return defs.ENOSPC; // No space
    }

    // For simplicity, handle one block at a time
    var block_buf: [blockdev.BLOCK_SIZE]u8 = undefined;

    // Read-modify-write if not aligned
    if (offset != 0 or data.len < blockdev.BLOCK_SIZE) {
        bf.device.readBlock(block_num, &block_buf) catch return defs.EIO;
    }

    // Copy data to block buffer
    const available = blockdev.BLOCK_SIZE - offset;
    const to_write = @min(data.len, available);
    @memcpy(block_buf[offset .. offset + to_write], data[0..to_write]);

    // Write block
    bf.device.writeBlock(block_num, &block_buf) catch return defs.EIO;

    bf.pos += to_write;
    return @as(isize, @intCast(to_write));
}

fn blockClose(file: *core.File) void {
    const bf: *BlockFile = @alignCast(@fieldParentPtr("file", file));
    bf.pos = 0;
    // Note: We don't free the BlockFile here as it's statically allocated
}

// Static allocation for block device files
var ramdisk_file: BlockFile = undefined;
var ramdisk_file_initialized = false;

pub fn getRamdiskFile() ?*BlockFile {
    if (!ramdisk_file_initialized) {
        if (ramdisk.getGlobalRamDisk()) |rd| {
            ramdisk_file = BlockFile.init(&rd.device);
            ramdisk_file_initialized = true;
            return &ramdisk_file;
        }
        return null;
    }
    // Reset position on each open
    ramdisk_file.pos = 0;
    return &ramdisk_file;
}
