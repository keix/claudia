const std = @import("std");
const types = @import("types.zig");
const physical = @import("physical.zig");
const uart = @import("../driver/uart/core.zig");

// Symbol exported from linker script
extern const _end: u8;

// Global allocator state management
const GlobalAllocator = struct {
    frame_allocator: physical.FrameAllocator,
    bitmap_storage: [16 * 1024]u8 align(8),
    initialized: bool,

    var instance: GlobalAllocator = .{
        .frame_allocator = undefined,
        .bitmap_storage = undefined,
        .initialized = false,
    };

    pub fn init() void {
        // Get kernel end address
        const kernel_end = @intFromPtr(&_end);
        const available_start = (kernel_end + types.PAGE_SIZE - 1) & ~(types.PAGE_SIZE - 1);

        // Physical memory info for QEMU virt machine
        const mem = types.PhysicalMemory{
            .base = 0x80000000,
            .size = 128 * 1024 * 1024, // 128MB
            .available = available_start,
        };

        instance.frame_allocator.init(mem, &instance.bitmap_storage);
        instance.initialized = true;
    }

    pub fn allocFrame() ?usize {
        std.debug.assert(instance.initialized);
        return instance.frame_allocator.alloc();
    }

    pub fn freeFrame(addr: usize) void {
        std.debug.assert(instance.initialized);
        instance.frame_allocator.free(addr);
    }

    pub fn getMemoryInfo() struct { total: usize, free: usize } {
        std.debug.assert(instance.initialized);
        return .{
            .total = instance.frame_allocator.total_frames * types.PAGE_SIZE,
            .free = instance.frame_allocator.free_frames * types.PAGE_SIZE,
        };
    }
};

// Export functions that operate on the global instance
pub const init = GlobalAllocator.init;
pub const allocFrame = GlobalAllocator.allocFrame;
pub const freeFrame = GlobalAllocator.freeFrame;
pub const getMemoryInfo = GlobalAllocator.getMemoryInfo;
