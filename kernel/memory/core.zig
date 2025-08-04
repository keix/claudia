const physical = @import("physical.zig");
const uart = @import("../driver/uart.zig");

pub const virtual = @import("virtual.zig");

pub const PAGE_SIZE = physical.PAGE_SIZE;
pub const FrameAllocator = physical.FrameAllocator;
pub const PageTable = virtual.PageTable;

// Global allocator and bitmap storage
var frame_allocator: FrameAllocator = undefined;
var bitmap_storage: [16 * 1024]u8 align(8) = undefined;

// Symbol exported from linker script
extern const _end: u8;

pub fn init() void {
    uart.puts("[memory] Initializing memory subsystem\n");

    // Get kernel end address
    const kernel_end = @intFromPtr(&_end);
    const available_start = (kernel_end + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1); // Align to page boundary

    // Physical memory info for QEMU virt machine
    const mem = physical.PhysicalMemory{
        .base = 0x80000000,
        .size = 128 * 1024 * 1024, // 128MB
        .available = available_start,
    };

    frame_allocator.init(mem, &bitmap_storage);

    uart.puts("[memory] Physical memory initialized: ");
    uart.putHex(frame_allocator.free_frames);
    uart.puts(" free frames (");
    uart.putHex(frame_allocator.free_frames * PAGE_SIZE);
    uart.puts(" bytes)\n");
}

pub fn initVirtual() !void {
    try virtual.setupKernelPageTable();
}

pub fn enableMMU() void {
    virtual.enableMMU();
}

pub fn allocFrame() ?usize {
    return frame_allocator.alloc();
}

pub fn freeFrame(addr: usize) void {
    frame_allocator.free(addr);
}

// Debug info
pub fn getMemoryInfo() struct { total: usize, free: usize } {
    return .{
        .total = frame_allocator.total_frames * PAGE_SIZE,
        .free = frame_allocator.free_frames * PAGE_SIZE,
    };
}
