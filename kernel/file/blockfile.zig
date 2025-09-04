// Block device file wrapper
const std = @import("std");
const core = @import("core.zig");
const types = @import("types.zig");
const defs = @import("abi");
const blockdev = @import("../driver/blockdev.zig");
const ramdisk = @import("../driver/ramdisk.zig");
const simplefs_ops = @import("../fs/simplefs_ops.zig");

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

    pub fn lseek(self: *BlockFile, offset: i64, whence: u32) isize {
        const new_pos = switch (whence) {
            0 => offset, // SEEK_SET
            1 => @as(i64, @intCast(self.pos)) + offset, // SEEK_CUR
            2 => blk: { // SEEK_END
                // For block devices, use device size
                const size = @as(i64, @intCast(self.device.total_blocks * blockdev.BLOCK_SIZE));
                break :blk size + offset;
            },
            else => return defs.EINVAL,
        };

        // Check bounds
        if (new_pos < 0) return defs.EINVAL;

        self.pos = @as(u64, @intCast(new_pos));
        return @as(isize, @intCast(self.pos));
    }
};

// File operations for block devices
const BlockFileOps = core.FileOperations{
    .read = blockRead,
    .write = blockWrite,
    .close = blockClose,
    .lseek = blockLseek,
};

fn blockRead(file: *core.File, buffer: []u8) isize {
    // Get BlockFile from File pointer using offset calculation
    const bf_ptr = @intFromPtr(file) - @offsetOf(BlockFile, "file");
    const bf: *BlockFile = @alignCast(@as(*BlockFile, @ptrFromInt(bf_ptr)));

    // Check if this is a SimpleFS file read
    if (simplefs_ops.handleFileRead(buffer)) |bytes_read| {
        return @as(isize, @intCast(bytes_read));
    } else |_| {
        // Regular block-aligned read
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
}

fn blockWrite(file: *core.File, data: []const u8) isize {
    // Get BlockFile from File pointer using offset calculation
    const bf_ptr = @intFromPtr(file) - @offsetOf(BlockFile, "file");
    const bf: *BlockFile = @alignCast(@as(*BlockFile, @ptrFromInt(bf_ptr)));

    // Check if this is a SimpleFS command (first byte >= 0x00 and <= 0x03)
    if (data.len > 0 and data[0] >= 0x00 and data[0] <= 0x03) {
        // Handle SimpleFS command
        _ = simplefs_ops.handleCommand(data) catch |err| {
            return switch (err) {
                error.InvalidCommand => defs.EINVAL,
                error.FileNotFound => defs.ENOENT,
                error.NoSpace => defs.ENOSPC,
                error.NameTooLong => defs.ENAMETOOLONG,
                else => defs.EIO,
            };
        };
        // Reset position after command for subsequent reads
        bf.pos = 0;
        return @intCast(data.len); // Return full command length as written
    }

    // Regular block-aligned write
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
    // Get BlockFile from File pointer using offset calculation
    const bf_ptr = @intFromPtr(file) - @offsetOf(BlockFile, "file");
    const bf: *BlockFile = @alignCast(@as(*BlockFile, @ptrFromInt(bf_ptr)));
    bf.pos = 0;
    // Note: We don't free the BlockFile here as it's statically allocated
}

fn blockLseek(file: *core.File, offset: i64, whence: u32) isize {
    // Get BlockFile from File pointer using offset calculation
    const bf_ptr = @intFromPtr(file) - @offsetOf(BlockFile, "file");
    const bf: *BlockFile = @alignCast(@as(*BlockFile, @ptrFromInt(bf_ptr)));
    return bf.lseek(offset, whence);
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
