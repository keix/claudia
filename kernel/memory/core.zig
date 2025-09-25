// Memory subsystem public API

const allocator = @import("allocator.zig");
const kalloc = @import("kalloc.zig");

pub const types = @import("types.zig");
pub const virtual = @import("virtual.zig");

// Re-export commonly used types
pub const PageTable = virtual.PageTable;
pub const kernel_page_table = &virtual.kernel_page_table;

pub fn init() void {
    allocator.init();
}

pub fn initVirtual() !void {
    try virtual.setupKernelPageTable();
}

pub fn enableMMU() void {
    virtual.enableMMU();
}

// Frame allocation API
pub const allocFrame = allocator.allocFrame;
pub const freeFrame = allocator.freeFrame;
pub const getMemoryInfo = allocator.getMemoryInfo;
