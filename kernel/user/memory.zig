// User memory management for Claudia kernel

const std = @import("std");
const types = @import("../memory/types.zig");
const allocator = @import("../memory/allocator.zig");
const virtual = @import("../memory/virtual.zig");

// User memory layout constants
pub const USER_CODE_BASE: u64 = 0x10000000;
pub const USER_CODE_SIZE: usize = 16 * types.PAGE_SIZE;
pub const USER_STACK_BASE: u64 = 0x20000000;
pub const USER_STACK_SIZE: usize = 16 * types.PAGE_SIZE;
pub const USER_HEAP_BASE: u64 = 0x30000000;
pub const USER_HEAP_SIZE: usize = 16 * types.PAGE_SIZE;

const MAX_REGION_PAGES: usize = 16;

pub const UserRegion = struct {
    virtual_base: u64,
    size: usize,
    physical_frames: [MAX_REGION_PAGES]?u64,
    permissions: u8,
    allocated: bool,
};
pub const UserMemoryContext = struct {
    code_region: UserRegion,
    stack_region: UserRegion,
    heap_region: UserRegion,
    page_table: ?virtual.PageTable,

    pub fn init() UserMemoryContext {
        return UserMemoryContext{
            .code_region = UserRegion{
                .virtual_base = USER_CODE_BASE,
                .size = USER_CODE_SIZE,
                .physical_frames = [_]?u64{null} ** MAX_REGION_PAGES,
                .permissions = virtual.PTE_R | virtual.PTE_X | virtual.PTE_U,
                .allocated = false,
            },
            .stack_region = UserRegion{
                .virtual_base = USER_STACK_BASE,
                .size = USER_STACK_SIZE,
                .physical_frames = [_]?u64{null} ** MAX_REGION_PAGES,
                .permissions = virtual.PTE_R | virtual.PTE_W | virtual.PTE_U,
                .allocated = false,
            },
            .heap_region = UserRegion{
                .virtual_base = USER_HEAP_BASE,
                .size = USER_HEAP_SIZE,
                .physical_frames = [_]?u64{null} ** MAX_REGION_PAGES,
                .permissions = virtual.PTE_R | virtual.PTE_W | virtual.PTE_U, // Read + Write + User
                .allocated = false,
            },
            .page_table = null,
        };
    }

    pub fn createPageTable(self: *UserMemoryContext) !void {
        if (self.page_table != null) {
            return;
        }

        var new_page_table = virtual.PageTable{
            .root_ppn = 0,
        };

        try new_page_table.init();
        self.page_table = new_page_table;
    }

    pub fn mapRegion(self: *UserMemoryContext, region: *const UserRegion) !void {
        if (self.page_table == null or !region.allocated) {
            return;
        }

        var page_table = &self.page_table.?;
        const page_count = (region.size + types.PAGE_SIZE - 1) / types.PAGE_SIZE;
        var i: usize = 0;

        while (i < page_count) : (i += 1) {
            const virtual_addr = region.virtual_base + (i * types.PAGE_SIZE);
            const physical_frame = region.physical_frames[i] orelse continue;

            try page_table.map(virtual_addr, physical_frame, region.permissions);
        }
    }

    pub fn setupAddressSpace(self: *UserMemoryContext) !void {
        try self.createPageTable();
        if (!allocateRegion(&self.code_region)) {
            return error.OutOfMemory;
        }
        if (!allocateRegion(&self.stack_region)) {
            deallocateRegion(&self.code_region);
            return error.OutOfMemory;
        }
        if (!allocateRegion(&self.heap_region)) {
            deallocateRegion(&self.code_region);
            deallocateRegion(&self.stack_region);
            return error.OutOfMemory;
        }
        try self.mapRegion(&self.code_region);
        try self.mapRegion(&self.stack_region);
        try self.mapRegion(&self.heap_region);
    }

    pub fn getPageTablePPN(self: *const UserMemoryContext) ?u64 {
        if (self.page_table) |*pt| {
            return pt.root_ppn;
        }
        return null;
    }

    pub fn deinit(self: *UserMemoryContext) void {
        deallocateRegion(&self.code_region);
        deallocateRegion(&self.stack_region);
        deallocateRegion(&self.heap_region);

        if (self.page_table) |*pt| {
            _ = pt; // TODO: Free page table pages
        }
        self.page_table = null;
    }
};

pub fn allocateRegion(region: *UserRegion) bool {
    if (region.allocated) {
        return true;
    }

    const frame_count = (region.size + types.PAGE_SIZE - 1) / types.PAGE_SIZE;
    if (frame_count > MAX_REGION_PAGES) {
        return false;
    }
    for (0..MAX_REGION_PAGES) |i| {
        region.physical_frames[i] = null;
    }

    var i: usize = 0;
    while (i < frame_count) : (i += 1) {
        const frame = allocator.allocFrame();
        if (frame) |f| {
            region.physical_frames[i] = f;
        } else {
            deallocateRegion(region);
            return false;
        }
    }

    region.allocated = true;
    return true;
}

pub fn deallocateRegion(region: *UserRegion) void {
    if (!region.allocated) {
        return;
    }

    for (region.physical_frames) |frame_opt| {
        if (frame_opt) |frame| {
            allocator.freeFrame(frame);
        }
    }

    for (0..MAX_REGION_PAGES) |i| {
        region.physical_frames[i] = null;
    }

    region.allocated = false;
}

pub fn getPhysicalAddress(region: *const UserRegion, virtual_addr: u64) ?u64 {
    if (!region.allocated) {
        return null;
    }

    if (virtual_addr < region.virtual_base or
        virtual_addr >= region.virtual_base + region.size)
    {
        return null;
    }

    const offset = virtual_addr - region.virtual_base;
    const frame_index = offset / types.PAGE_SIZE;
    const page_offset = offset % types.PAGE_SIZE;

    if (frame_index >= region.physical_frames.len) {
        return null;
    }

    if (region.physical_frames[frame_index]) |frame| {
        return frame + page_offset;
    }

    return null;
}

pub fn copyToRegion(region: *const UserRegion, offset: usize, data: []const u8) bool {
    if (!region.allocated or offset + data.len > region.size) {
        return false;
    }

    var bytes_copied: usize = 0;
    while (bytes_copied < data.len) {
        const virtual_addr = region.virtual_base + offset + bytes_copied;
        const physical_addr = getPhysicalAddress(region, virtual_addr) orelse return false;

        // Handle page boundary crossing
        const page_offset = (offset + bytes_copied) % types.PAGE_SIZE;
        const bytes_in_page = @min(types.PAGE_SIZE - page_offset, data.len - bytes_copied);

        const dest = @as([*]u8, @ptrFromInt(physical_addr));
        @memcpy(dest[0..bytes_in_page], data[bytes_copied .. bytes_copied + bytes_in_page]);

        bytes_copied += bytes_in_page;
    }

    return true;
}

pub fn init() void {
    // Initialize user memory management
}
