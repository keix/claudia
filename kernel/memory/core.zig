// Memory subsystem public API

const allocator = @import("allocator.zig");
const uart = @import("../driver/uart/core.zig");

pub const types = @import("types.zig");
pub const virtual = @import("virtual.zig");

// Re-export commonly used types
pub const PAGE_SIZE = types.PAGE_SIZE;
pub const PageTable = virtual.PageTable;

// Initialize physical memory allocator
pub fn init() void {
    uart.puts("[memory] Initializing memory subsystem\n");
    allocator.init();
}

// Initialize virtual memory
pub fn initVirtual() !void {
    try virtual.setupKernelPageTable();
}

// Enable MMU
pub fn enableMMU() void {
    virtual.enableMMU();
}

// Frame allocation API
pub const allocFrame = allocator.allocFrame;
pub const freeFrame = allocator.freeFrame;
pub const getMemoryInfo = allocator.getMemoryInfo;
