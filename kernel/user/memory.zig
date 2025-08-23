// User memory management for Claudia kernel

const std = @import("std");
const types = @import("../memory/types.zig");
const allocator = @import("../memory/allocator.zig");
const virtual = @import("../memory/virtual.zig");

// Import memory layout constants from types.zig
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
                .permissions = virtual.PTE_R | virtual.PTE_W | virtual.PTE_U, // Read + Write + User
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

        const uart = @import("../driver/uart/core.zig");
        uart.puts("[UserMemoryContext] createPageTable called\n");

        // Allocate PageTable struct from kernel heap
        const kalloc = @import("../memory/kalloc.zig");
        const pt_ptr = try kalloc.kcreate(virtual.PageTable);

        // Initialize the PageTable struct
        // init() will allocate the root page internally
        try pt_ptr.init();
        self.page_table = pt_ptr;
        
        uart.puts("[UserMemoryContext] Created page table with root_ppn: 0x");
        uart.putHex(pt_ptr.root_ppn);
        uart.puts("\n");
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
            const uart = @import("../driver/uart/core.zig");
            uart.puts("[setupAddressSpace] ERROR: addKernelMappings failed: ");
            switch (err) {
                error.OutOfMemory => uart.puts("OutOfMemory"),
                error.KernelMappingFailed => uart.puts("KernelMappingFailed"),
                else => uart.puts("Unknown error"),
            }
            uart.puts("\n");
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

    // Add kernel global mappings to user page table
    // This includes: kernel text/data/bss, MMIO, trampoline, AND kernel stack
    fn addKernelMappings(self: *UserMemoryContext) !void {
        const uart = @import("../driver/uart/core.zig");
        
        uart.puts("[addKernelMappings] Adding kernel mappings to user page table\n");
        
        if (self.page_table == null) {
            uart.puts("  ERROR: Page table is null!\n");
            return;
        }

        const page_table = self.page_table.?;
        uart.puts("  User page table root_ppn: 0x");
        uart.putHex(page_table.root_ppn);
        uart.puts("\n");

        // Build all kernel global mappings
        uart.puts("  Calling buildKernelGlobalMappings...\n");
        try virtual.buildKernelGlobalMappings(page_table);
        
        // Check if mapping survived
        page_table.checkCriticalPTE("After buildKernelGlobalMappings in addKernelMappings");

        // Explicitly ensure kernel stack is mapped (defensive programming)
        // This is redundant as buildKernelGlobalMappings() already calls it,
        // but ensures kernel stack is always accessible from trap handler
        try mapKernelStackToPageTable(page_table);
        
        // CRITICAL: Verify kernel mappings were actually added
        uart.puts("  Verifying kernel mappings in user PT...\n");
        
        // Check a few critical kernel addresses
        const test_addrs = [_]u64{
            0x80200000, // Kernel code start
            0x80210000, // More kernel code
            0x8021b000, // Near the fault address
            0x80400000, // Kernel heap
            types.KERNEL_STACK_BASE, // Kernel stack
        };
        
        for (test_addrs) |addr| {
            if (page_table.translate(addr)) |phys| {
                uart.puts("    0x");
                uart.putHex(addr);
                uart.puts(" -> 0x");
                uart.putHex(phys);
                uart.puts(" OK\n");
            } else {
                uart.puts("    ERROR: 0x");
                uart.putHex(addr);
                uart.puts(" NOT MAPPED!\n");
                return error.KernelMappingFailed;
            }
        }
    }

    // DEPRECATED: Old approach - used dynamic stack mapping instead of fixed kernel stack
    // Now superseded by mapKernelStackToPageTable() in buildKernelGlobalMappings()
    // TODO: Remove this function entirely once confirmed unused
    pub fn mapCurrentStack(self: *UserMemoryContext, stack_ptr: u64, stack_size: usize) !void {
        _ = self;
        _ = stack_ptr;
        _ = stack_size; // Silence unused parameter warnings
        // NO-OP: This function is deprecated and should not be used
        return;
    }

    // Debug function to verify mappings
    pub fn verifyMapping(self: *UserMemoryContext, vaddr: u64) bool {
        if (self.page_table == null) return false;

        const page_table = self.page_table.?;
        const result = page_table.translate(vaddr) != null;
        
        // Extra debug for critical addresses
        if (vaddr == 0x8021b000 and !result) {
            const uart = @import("../driver/uart/core.zig");
            uart.puts("[verifyMapping] ERROR: 0x8021b000 not found!\n");
            uart.puts("  Page table root_ppn: 0x");
            uart.putHex(page_table.root_ppn);
            uart.puts("\n");
        }
        
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
            // First deinit the page table (frees internal pages)
            pt.deinit();

            // Then free the page table struct itself
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

// FIXME: Uses physical direct access assuming kernel VA=PA identity mapping
// This will break when kernel moves to high-only mapping. Need to replace with:
// A) Temporary kernel mapping window (kmap/kunmap), or
// B) Switch to kernel PT temporarily during copy
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

        // WARNING: Direct physical access - assumes kernel VA=PA identity mapping
        const dest = @as([*]u8, @ptrFromInt(physical_addr));
        @memcpy(dest[0..bytes_in_page], data[bytes_copied .. bytes_copied + bytes_in_page]);

        bytes_copied += bytes_in_page;
    }

    return true;
}

// Zero memory in a user region (for .bss initialization)
pub fn zeroRegion(region: *UserRegion, offset: usize, len: usize) bool {
    if (!region.allocated) {
        return false;
    }

    if (offset + len > region.size) {
        return false; // Out of bounds
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

        // Zero the memory range in this page
        const zero_len = zero_end - zero_start;
        const target_addr = physical_addr + zero_start;
        const target_ptr = @as([*]u8, @ptrFromInt(target_addr));
        @memset(target_ptr[0..zero_len], 0);
    }

    return true;
}

// FIXME: Global kernel stack storage - single stack for all processes
// This will cause conflicts when multiple processes run concurrently.
// Future: Move to per-process kernel stack in PCB (Process Control Block)
var kernel_stack_frames: [4]?u64 = [_]?u64{null} ** 4;

pub fn init() void {
    // Allocate physical frames for kernel stack
    for (0..4) |i| {
        kernel_stack_frames[i] = allocator.allocFrame();
    }
}

// Get kernel stack top address from common kernel high mapping
// Returns VA in kernel region (0x87F00000+), NOT a local array address
pub fn getKernelStackTop() u64 {
    return KERNEL_STACK_BASE + KERNEL_STACK_SIZE - 8;
}

// Map kernel stack to any page table (called from buildKernelGlobalMappings)
pub fn mapKernelStackToPageTable(page_table: *virtual.PageTable) !void {
    // Map each kernel stack page
    for (0..4) |i| {
        if (kernel_stack_frames[i]) |frame| {
            const vaddr = KERNEL_STACK_BASE + @as(u64, @intCast(i * types.PAGE_SIZE));
            try page_table.map(vaddr, frame, virtual.PTE_R | virtual.PTE_W | virtual.PTE_G); // U=0: kernel only
        }
    }
}

// Add ELF segment mapping functionality
pub fn addElfSegment(context: *UserMemoryContext, virtual_addr: u64, size: usize, permissions: u8) !*UserRegion {
    if (context.elf_segment_count >= MAX_ELF_SEGMENTS) {
        return error.TooManySegments;
    }

    // Check for overlap with existing segments and fixed regions
    const end_addr = virtual_addr + @as(u64, size);

    // Check overlap with fixed regions
    if (checkOverlapWithFixedRegion(virtual_addr, end_addr)) |_| {
        return error.SegmentOverlap;
    }

    // Check overlap with existing ELF segments
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

    // Clear physical frames
    for (0..MAX_REGION_PAGES) |i| {
        segment.physical_frames[i] = null;
    }

    context.elf_segment_count += 1;
    return segment;
}

// Map all ELF segments to user page table
pub fn mapElfSegments(context: *UserMemoryContext) !void {
    const page_table = context.page_table orelse return error.NoPageTable;

    for (0..context.elf_segment_count) |i| {
        const segment = &context.elf_segments[i];
        if (!segment.allocated) continue;

        // Map each page of the segment
        const page_count = (segment.size + types.PAGE_SIZE - 1) / types.PAGE_SIZE;
        for (0..page_count) |page_idx| {
            if (segment.physical_frames[page_idx]) |frame| {
                const vaddr = segment.virtual_base + @as(u64, @intCast(page_idx * types.PAGE_SIZE));
                try page_table.map(vaddr, frame, segment.permissions);
            }
        }
    }
}

// Check if virtual address range overlaps with any fixed region
fn checkOverlapWithFixedRegion(start: u64, end: u64) ?[]const u8 {
    // Check USER_CODE_BASE region
    if (!(end <= USER_CODE_BASE or start >= USER_CODE_BASE + USER_CODE_SIZE)) {
        return "USER_CODE";
    }

    // Check USER_STACK_BASE region
    if (!(end <= USER_STACK_BASE or start >= USER_STACK_BASE + USER_STACK_SIZE)) {
        return "USER_STACK";
    }

    // Check USER_HEAP_BASE region
    if (!(end <= USER_HEAP_BASE or start >= USER_HEAP_BASE + USER_HEAP_SIZE)) {
        return "USER_HEAP";
    }

    // Check KERNEL regions (should not overlap with user segments)
    const KERNEL_BASE = 0x80000000;
    const KERNEL_END = 0x90000000; // Approximate kernel region end
    if (!(end <= KERNEL_BASE or start >= KERNEL_END)) {
        return "KERNEL";
    }

    return null; // No overlap
}
