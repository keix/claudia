const types = @import("types.zig");

// Re-export for backward compatibility
pub const PAGE_SIZE = types.PAGE_SIZE;
pub const PAGE_SHIFT = types.PAGE_SHIFT;

pub const FrameAllocator = struct {
    bitmap: []u8,
    total_frames: usize,
    free_frames: usize,
    base_addr: usize,

    const Self = @This();

    pub fn init(self: *Self, mem: types.PhysicalMemory, bitmap_storage: []u8) void {
        self.base_addr = mem.base;
        self.bitmap = bitmap_storage;

        // Calculate number of frames
        const reserved_frames = (mem.available - mem.base) >> PAGE_SHIFT;
        self.total_frames = mem.size >> PAGE_SHIFT;
        self.free_frames = self.total_frames - reserved_frames;

        // Initialize bitmap (1 = used)
        const bitmap_bytes = (self.total_frames + 7) / 8;
        for (0..bitmap_bytes) |i| {
            self.bitmap[i] = 0xFF;
        }

        // Mark available frames as free (0 = free)
        for (reserved_frames..self.total_frames) |frame| {
            self.clearBit(frame);
        }
    }

    pub fn alloc(self: *Self) ?usize {
        if (self.free_frames == 0) return null;

        // Find first free bit in bitmap
        const bitmap_bytes = (self.total_frames + 7) / 8;
        for (0..bitmap_bytes) |byte_idx| {
            if (self.bitmap[byte_idx] != 0xFF) {
                // This byte has free bits
                for (0..8) |bit_idx| {
                    const frame = byte_idx * 8 + bit_idx;
                    if (frame >= self.total_frames) break;

                    if (!self.testBit(frame)) {
                        self.setBit(frame);
                        self.free_frames -= 1;
                        return self.frameToAddr(frame);
                    }
                }
            }
        }
        return null;
    }

    pub fn free(self: *Self, addr: usize) void {
        // Validate address
        if (addr < self.base_addr or addr >= self.base_addr + (self.total_frames << PAGE_SHIFT)) {
            return; // Invalid address
        }
        if ((addr & (PAGE_SIZE - 1)) != 0) {
            return; // Alignment error
        }

        const frame = self.addrToFrame(addr);
        if (self.testBit(frame)) {
            self.clearBit(frame);
            self.free_frames += 1;
        }
    }

    fn frameToAddr(self: *Self, frame: usize) usize {
        return self.base_addr + (frame << PAGE_SHIFT);
    }

    fn addrToFrame(self: *Self, addr: usize) usize {
        return (addr - self.base_addr) >> PAGE_SHIFT;
    }

    fn setBit(self: *Self, frame: usize) void {
        const byte_idx = frame / 8;
        const bit_idx = @as(u3, @truncate(frame % 8));
        self.bitmap[byte_idx] |= (@as(u8, 1) << bit_idx);
    }

    fn clearBit(self: *Self, frame: usize) void {
        const byte_idx = frame / 8;
        const bit_idx = @as(u3, @truncate(frame % 8));
        self.bitmap[byte_idx] &= ~(@as(u8, 1) << bit_idx);
    }

    fn testBit(self: *Self, frame: usize) bool {
        const byte_idx = frame / 8;
        const bit_idx = @as(u3, @truncate(frame % 8));
        return (self.bitmap[byte_idx] & (@as(u8, 1) << bit_idx)) != 0;
    }
};
