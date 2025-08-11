// Kernel heap allocator for Claudia
// Simple bump allocator for now, no free support yet

const std = @import("std");
const types = @import("types.zig");
const allocator = @import("allocator.zig");
const uart = @import("../driver/uart/core.zig");

// Use heap configuration from types.zig
const HEAP_BASE = types.KERNEL_HEAP_BASE;
const HEAP_SIZE = types.KERNEL_HEAP_SIZE;

// Heap state
var heap_start: u64 = 0;
var heap_end: u64 = 0;
var heap_current: u64 = 0;
var initialized: bool = false;

// Initialize kernel heap
pub fn init() !void {
    if (initialized) return;

    uart.puts("[kalloc] Initializing kernel heap at ");
    uart.putHex(HEAP_BASE);
    uart.puts(" size ");
    uart.putHex(HEAP_SIZE);
    uart.puts("\n");

    const pages_needed = (HEAP_SIZE + types.PAGE_SIZE - 1) / types.PAGE_SIZE;
    heap_start = HEAP_BASE;
    heap_end = HEAP_BASE + (pages_needed * types.PAGE_SIZE);
    heap_current = heap_start;

    // The heap uses high kernel addresses that are identity-mapped
    // in the kernel page table (0x88000000+). These addresses are
    // within the physical RAM range and will work with VA=PA mapping.

    initialized = true;
    uart.puts("[kalloc] Kernel heap initialized\n");
}

// Allocate memory from kernel heap (bump allocator)
pub fn kalloc(size: usize, alignment: usize) ?[*]u8 {
    if (!initialized) return null;

    const required_align = if (alignment == 0) @alignOf(usize) else alignment;

    // Align current position
    const aligned_current = std.mem.alignForward(u64, heap_current, required_align);
    const end_addr = aligned_current + size;

    // Check if we have enough space
    if (end_addr > heap_end) {
        uart.puts("[kalloc] Out of heap memory\n");
        return null;
    }

    const ptr = @as([*]u8, @ptrFromInt(aligned_current));
    heap_current = end_addr;

    return ptr;
}

// Free memory (no-op for now in bump allocator)
pub fn kfree(ptr: [*]u8, size: usize) void {
    _ = ptr;
    _ = size;
    // TODO: Implement proper free when we upgrade to a real allocator
}

// Create a new object of type T in kernel heap
pub fn kcreate(comptime T: type) !*T {
    const mem = kalloc(@sizeOf(T), @alignOf(T)) orelse return error.OutOfMemory;
    const obj = @as(*T, @ptrCast(@alignCast(mem)));
    obj.* = std.mem.zeroes(T);
    return obj;
}

// Destroy an object (no-op for now)
pub fn kdestroy(ptr: anytype) void {
    _ = ptr;
    // TODO: Implement when we have proper free
}

// Get heap statistics
pub fn getHeapStats() struct { used: usize, total: usize } {
    if (!initialized) return .{ .used = 0, .total = 0 };

    return .{
        .used = heap_current - heap_start,
        .total = heap_end - heap_start,
    };
}
