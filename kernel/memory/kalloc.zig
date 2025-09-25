// Kernel heap allocator for Claudia
const std = @import("std");
const types = @import("types.zig");
const allocator = @import("allocator.zig");

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

    const pages_needed = types.alignPageUp(HEAP_SIZE) / types.PAGE_SIZE;
    heap_start = HEAP_BASE;
    heap_end = HEAP_BASE + (pages_needed * types.PAGE_SIZE);
    heap_current = heap_start;

    // The heap uses high kernel addresses that are identity-mapped
    // in the kernel page table (0x88000000+). These addresses are
    // within the physical RAM range and will work with VA=PA mapping.

    initialized = true;
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
        return null;
    }

    const ptr = @as([*]u8, @ptrFromInt(aligned_current));
    heap_current = end_addr;

    return ptr;
}

// Free memory (no-op for bump allocator)
// TODO: Implement proper free when we upgrade to a real allocator
pub fn kfree(ptr: [*]u8, size: usize) void {
    _ = ptr;
    _ = size;
}

// Create a new object of type T in kernel heap
pub fn kcreate(comptime T: type) !*T {
    const mem = kalloc(@sizeOf(T), @alignOf(T)) orelse return error.OutOfMemory;
    const obj = @as(*T, @ptrCast(@alignCast(mem)));
    obj.* = std.mem.zeroes(T);
    return obj;
}

/// Destroy an object (no-op for now)
/// TODO: Implement when we have proper free
///
/// Currently just a wrapper around kfree. When we implement proper
/// memory management, this will also handle calling destructors.
pub fn kdestroy(ptr: anytype) void {
    _ = ptr;

    // Future: Call destructor if type has deinit method
    // Future: Zero memory before freeing for security
}
