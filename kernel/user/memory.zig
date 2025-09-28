// User memory management

const std = @import("std");
const types = @import("../memory/types.zig");
const allocator = @import("../memory/allocator.zig");
const virtual = @import("../memory/virtual.zig");

pub const USER_CODE_BASE = types.USER_CODE_BASE;
pub const USER_CODE_SIZE = types.USER_CODE_SIZE;
pub const USER_STACK_BASE = types.USER_STACK_BASE;
pub const USER_STACK_SIZE = types.USER_STACK_SIZE;
pub const USER_HEAP_BASE = types.USER_HEAP_BASE;
pub const USER_HEAP_SIZE = types.USER_HEAP_SIZE;
pub const KERNEL_STACK_BASE = types.KERNEL_STACK_BASE;
pub const KERNEL_STACK_SIZE = types.KERNEL_STACK_SIZE;

const MAX_REGION_PAGES: usize = 16;

pub const UserRegion = struct {
    virtual_base: u64,
    size: usize,
    physical_frames: [MAX_REGION_PAGES]?u64,
    permissions: u8,
    allocated: bool,
};
const MAX_ELF_SEGMENTS: usize = 8;

pub const UserMemoryContext = struct {
    code_region: UserRegion,
    stack_region: UserRegion,
    heap_region: UserRegion,
    elf_segments: [MAX_ELF_SEGMENTS]UserRegion,
    elf_segment_count: usize,
    page_table: ?*virtual.PageTable,

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
                .permissions = virtual.PTE_R | virtual.PTE_W | virtual.PTE_U,
                .allocated = false,
            },
            .elf_segments = [_]UserRegion{UserRegion{
                .virtual_base = 0,
                .size = 0,
                .physical_frames = [_]?u64{null} ** MAX_REGION_PAGES,
                .permissions = 0,
                .allocated = false,
            }} ** MAX_ELF_SEGMENTS,
            .elf_segment_count = 0,
            .page_table = null,
        };
    }

    pub fn createPageTable(self: *UserMemoryContext) !void {
        if (self.page_table != null) {
            return;
        }

        const kalloc = @import("../memory/kalloc.zig");
        const pt_ptr = try kalloc.kcreate(virtual.PageTable);
        try pt_ptr.init();
        self.page_table = pt_ptr;
    }

    pub fn mapRegion(self: *UserMemoryContext, region: *const UserRegion) !void {
        if (self.page_table == null or !region.allocated) {
            return;
        }

        const page_table = self.page_table.?;
        const page_count = (region.size + types.PAGE_SIZE - 1) / types.PAGE_SIZE;
        var i: usize = 0;

        while (i < page_count) : (i += 1) {
            const virtual_addr = region.virtual_base + @as(u64, @intCast(i * types.PAGE_SIZE));
            const physical_frame = region.physical_frames[i] orelse continue;

            try page_table.map(virtual_addr, physical_frame, region.permissions);
        }
    }

    pub fn setupAddressSpace(self: *UserMemoryContext) !void {
        try self.createPageTable();

        // Add kernel mappings for trap handling
        self.addKernelMappings() catch |err| {
            return err;
        };

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

    fn addKernelMappings(self: *UserMemoryContext) !void {
        if (self.page_table == null) {
            return;
        }

        const page_table = self.page_table.?;

        try virtual.buildKernelGlobalMappings(page_table);
        try mapKernelStackToPageTable(page_table);

        // Verify critical kernel mappings
        const critical_addrs = [_]u64{ 0x80200000, 0x8021b000, types.KERNEL_STACK_BASE };
        for (critical_addrs) |addr| {
            if (page_table.translate(addr) == null) return error.KernelMappingFailed;
        }
    }

    pub fn verifyMapping(self: *UserMemoryContext, vaddr: u64) bool {
        if (self.page_table == null) return false;

        const page_table = self.page_table.?;
        const result = page_table.translate(vaddr) != null;

        return result;
    }

    pub fn getPageTablePPN(self: *const UserMemoryContext) ?u64 {
        if (self.page_table) |pt| {
            return pt.root_ppn;
        }
        return null;
    }

    pub fn deinit(self: *UserMemoryContext) void {
        deallocateRegion(&self.code_region);
        deallocateRegion(&self.stack_region);
        deallocateRegion(&self.heap_region);

        if (self.page_table) |pt| {
            pt.deinit();
            const kalloc = @import("../memory/kalloc.zig");
            kalloc.kdestroy(pt);
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
        virtual_addr >= region.virtual_base + @as(u64, region.size))
    {
        return null;
    }

    const offset = virtual_addr - region.virtual_base;
    const frame_index = @as(usize, @intCast(offset / types.PAGE_SIZE));
    const page_offset = @as(usize, @intCast(offset % types.PAGE_SIZE));

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
        const virtual_addr = region.virtual_base + @as(u64, @intCast(offset + bytes_copied));
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

pub fn zeroRegion(region: *UserRegion, offset: usize, len: usize) bool {
    if (!region.allocated) {
        return false;
    }

    if (offset + len > region.size) {
        return false;
    }

    const start_page = offset / types.PAGE_SIZE;
    const end_page = (offset + len + types.PAGE_SIZE - 1) / types.PAGE_SIZE;

    for (start_page..end_page) |page_idx| {
        if (page_idx >= MAX_REGION_PAGES) break;

        const physical_frame = region.physical_frames[page_idx] orelse continue;
        const physical_addr = physical_frame + types.PAGE_SIZE * page_idx;

        // Calculate offset within this page
        const page_start = page_idx * types.PAGE_SIZE;
        const zero_start = if (offset > page_start) offset - page_start else 0;
        const zero_end = if (offset + len < page_start + types.PAGE_SIZE)
            offset + len - page_start
        else
            types.PAGE_SIZE;

        if (zero_start >= zero_end) continue;

        const zero_len = zero_end - zero_start;
        const target_addr = physical_addr + zero_start;
        const target_ptr = @as([*]u8, @ptrFromInt(target_addr));
        @memset(target_ptr[0..zero_len], 0);
    }

    return true;
}

var kernel_stack_frames: [4]?u64 = [_]?u64{null} ** 4;

pub fn init() void {
    for (0..4) |i| {
        kernel_stack_frames[i] = allocator.allocFrame();
    }
}

pub fn getKernelStackTop() u64 {
    return KERNEL_STACK_BASE + KERNEL_STACK_SIZE - 8;
}

pub fn mapKernelStackToPageTable(page_table: *virtual.PageTable) !void {
    for (0..4) |i| {
        if (kernel_stack_frames[i]) |frame| {
            const vaddr = KERNEL_STACK_BASE + @as(u64, @intCast(i * types.PAGE_SIZE));
            try page_table.map(vaddr, frame, virtual.PTE_R | virtual.PTE_W | virtual.PTE_G);
        }
    }
}

pub fn addElfSegment(context: *UserMemoryContext, virtual_addr: u64, size: usize, permissions: u8) !*UserRegion {
    if (context.elf_segment_count >= MAX_ELF_SEGMENTS) {
        return error.TooManySegments;
    }

    const end_addr = virtual_addr + @as(u64, size);

    if (checkOverlapWithFixedRegion(virtual_addr, end_addr)) |_| {
        return error.SegmentOverlap;
    }

    for (0..context.elf_segment_count) |i| {
        const existing = &context.elf_segments[i];
        const existing_end = existing.virtual_base + @as(u64, existing.size);

        if (!(end_addr <= existing.virtual_base or virtual_addr >= existing_end)) {
            return error.SegmentOverlap;
        }
    }

    const segment = &context.elf_segments[context.elf_segment_count];
    segment.virtual_base = virtual_addr;
    segment.size = size;
    segment.permissions = permissions;
    segment.allocated = false;

    for (0..MAX_REGION_PAGES) |i| {
        segment.physical_frames[i] = null;
    }

    context.elf_segment_count += 1;
    return segment;
}

pub fn mapElfSegments(context: *UserMemoryContext) !void {
    const page_table = context.page_table orelse return error.NoPageTable;

    for (0..context.elf_segment_count) |i| {
        const segment = &context.elf_segments[i];
        if (!segment.allocated) continue;

        const page_count = (segment.size + types.PAGE_SIZE - 1) / types.PAGE_SIZE;
        for (0..page_count) |page_idx| {
            if (segment.physical_frames[page_idx]) |frame| {
                const vaddr = segment.virtual_base + @as(u64, @intCast(page_idx * types.PAGE_SIZE));
                try page_table.map(vaddr, frame, segment.permissions);
            }
        }
    }
}

fn checkOverlapWithFixedRegion(start: u64, end: u64) ?[]const u8 {
    if (!(end <= USER_CODE_BASE or start >= USER_CODE_BASE + USER_CODE_SIZE)) {
        return "USER_CODE";
    }

    if (!(end <= USER_STACK_BASE or start >= USER_STACK_BASE + USER_STACK_SIZE)) {
        return "USER_STACK";
    }

    if (!(end <= USER_HEAP_BASE or start >= USER_HEAP_BASE + USER_HEAP_SIZE)) {
        return "USER_HEAP";
    }

    const KERNEL_BASE = 0x80000000;
    const KERNEL_END = 0x90000000;
    if (!(end <= KERNEL_BASE or start >= KERNEL_END)) {
        return "KERNEL";
    }

    return null;
}
