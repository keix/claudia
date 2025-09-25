const std = @import("std");
const types = @import("types.zig");
const physical = @import("physical.zig");

// Symbol exported from linker script
extern const _end: u8;

// Constants for memory management
const MANAGED_MEMORY_SIZE = 256 * 1024 * 1024; // 256MB
const BITMAP_SIZE = 32 * 1024; // 32KB bitmap for 256MB with 4KB pages

// Global allocator state management
/// Global physical memory allocator singleton
/// Manages physical memory frames using a bitmap allocator
const GlobalAllocator = struct {
    frame_allocator: physical.FrameAllocator,
    bitmap_storage: [BITMAP_SIZE]u8 align(8),
    initialized: bool,

    var instance: GlobalAllocator = .{
        .frame_allocator = undefined,
        .bitmap_storage = std.mem.zeroes([BITMAP_SIZE]u8),
        .initialized = false,
    };

    pub fn init() void {
        if (instance.initialized) {
            // Already initialized, ignore duplicate calls
            return;
        }

        // Get kernel end address
        const kernel_end = @intFromPtr(&_end);
        const available_start = types.alignPageUp(kernel_end);

        // Physical memory info for QEMU virt machine
        const mem = types.PhysicalMemory{
            .base = types.KERNEL_BASE,
            .size = MANAGED_MEMORY_SIZE,
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
