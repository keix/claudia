// Memory subsystem public API

const allocator = @import("allocator.zig");
const kalloc = @import("kalloc.zig");

pub const types = @import("types.zig");
pub const virtual = @import("virtual.zig");

// Re-export commonly used types (but not constants - use types directly)
pub const PageTable = virtual.PageTable;
pub const kernel_page_table = &virtual.kernel_page_table;

// Initialize physical memory allocator
pub fn init() void {
    allocator.init();
}

// Initialize virtual memory and kernel heap
pub fn initVirtual() !void {
    try virtual.setupKernelPageTable();
    // Note: kalloc.init() is called from init.zig before MMU is enabled
}

// Enable MMU
pub fn enableMMU() void {
    virtual.enableMMU();
}

// Frame allocation API
pub const allocFrame = allocator.allocFrame;
pub const freeFrame = allocator.freeFrame;
pub const getMemoryInfo = allocator.getMemoryInfo;
