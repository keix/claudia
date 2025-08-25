// RAM disk implementation for Claudia
const std = @import("std");
const blockdev = @import("blockdev.zig");
const memory = @import("../memory/core.zig");
const kalloc = @import("../memory/kalloc.zig");
const defs = @import("abi");

pub const RamDisk = struct {
    device: blockdev.BlockDevice,
    data: []u8,

    pub fn getDataPtr(self: *RamDisk) []u8 {
        return self.data;
    }

    pub fn init(size_in_blocks: u64) !RamDisk {
        const total_size = size_in_blocks * blockdev.BLOCK_SIZE;

        // Allocate memory for the RAM disk using kernel allocator
        const data_ptr = kalloc.kalloc(total_size, 8) orelse return error.OutOfMemory;
        const data = data_ptr[0..total_size];

        // Initialize to zeros
        @memset(data, 0);

        var rd = RamDisk{
            .device = blockdev.BlockDevice.init("ramdisk", &RamDiskOps, size_in_blocks),
            .data = data,
        };

        // Set device data pointer to self
        rd.device.device_data = &rd;

        return rd;
    }

    pub fn deinit(self: *RamDisk) void {
        // Note: kalloc doesn't support free yet
        _ = self;
    }

    fn readBlock(dev: *blockdev.BlockDevice, block_num: u64, buffer: []u8) anyerror!void {
        const rd = @as(*RamDisk, @ptrCast(@alignCast(dev.device_data.?)));

        if (block_num >= dev.total_blocks) {
            return error.InvalidBlock;
        }

        const offset = block_num * blockdev.BLOCK_SIZE;
        @memcpy(buffer[0..blockdev.BLOCK_SIZE], rd.data[offset .. offset + blockdev.BLOCK_SIZE]);
    }

    fn writeBlock(dev: *blockdev.BlockDevice, block_num: u64, data: []const u8) anyerror!void {
        const rd = @as(*RamDisk, @ptrCast(@alignCast(dev.device_data.?)));

        if (block_num >= dev.total_blocks) {
            return error.InvalidBlock;
        }

        const offset = block_num * blockdev.BLOCK_SIZE;
        @memcpy(rd.data[offset .. offset + blockdev.BLOCK_SIZE], data[0..blockdev.BLOCK_SIZE]);
    }

    fn getSize(dev: *blockdev.BlockDevice) u64 {
        return dev.total_blocks;
    }
};

const RamDiskOps = blockdev.BlockDeviceOps{
    .read_block = RamDisk.readBlock,
    .write_block = RamDisk.writeBlock,
    .get_size = RamDisk.getSize,
};

// Global RAM disk instance (128KB = 256 blocks)
var global_ramdisk: ?RamDisk = null;

pub fn initGlobalRamDisk() !void {
    global_ramdisk = try RamDisk.init(256); // 128KB RAM disk
    // Fix device_data to point to the global instance
    if (global_ramdisk) |*rd| {
        rd.device.device_data = rd;
    }
}

pub fn getGlobalRamDisk() ?*RamDisk {
    if (global_ramdisk) |*rd| {
        return rd;
    }
    return null;
}
