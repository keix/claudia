const types = @import("types.zig");

// Use PAGE_SIZE and PAGE_SHIFT directly from types
const PAGE_SIZE = types.PAGE_SIZE;
const PAGE_SHIFT = types.PAGE_SHIFT;

// Frame allocator using a bitmap (1 = used, 0 = free)
pub const FrameAllocator = struct {
    bitmap: []u8,
    total_frames: usize,
    free_frames: usize,
    base_addr: usize,
    bitmap_bytes: usize,

    const Self = @This();

    pub fn init(self: *Self, mem: types.PhysicalMemory, bitmap_storage: []u8) void {
        self.base_addr = mem.base;
        self.bitmap = bitmap_storage;

        // Calculate number of frames
        const reserved_frames = (mem.available - mem.base) >> PAGE_SHIFT;
        self.total_frames = mem.size >> PAGE_SHIFT;
        self.free_frames = self.total_frames - reserved_frames;
        self.bitmap_bytes = (self.total_frames + 7) / 8;

        // Initialize bitmap (1 = used)
        for (0..self.bitmap_bytes) |i| {
            self.bitmap[i] = 0xFF;
        }

        // Mark available frames as free (0 = free)
        for (reserved_frames..self.total_frames) |frame| {
            self.clearBit(frame);
        }
    }

    pub fn alloc(self: *Self) ?usize {
        if (self.free_frames == 0) return null;

        // Find first free bit in bitmap using optimized search
        for (0..self.bitmap_bytes) |byte_idx| {
            const byte = self.bitmap[byte_idx];
            if (byte != 0xFF) {
                // Use @ctz to find first zero bit (inverted)
                const inverted = ~byte;
                const bit_idx = @ctz(inverted);
                const frame = byte_idx * 8 + bit_idx;

                if (frame >= self.total_frames) continue;

                self.setBit(frame);
                self.free_frames -= 1;
                return self.frameToAddr(frame);
            }
        }
        return null;
    }

    pub fn free(self: *Self, addr: usize) void {
        // Validate address range
        if (addr < self.base_addr or addr >= self.base_addr + (self.total_frames << PAGE_SHIFT)) {
            // In kernel context, invalid frees are often programming errors
            // Consider using std.debug.panic in debug builds
            return;
        }

        // Validate alignment
        if (!types.isPageAligned(addr)) {
            return;
        }

        const frame = self.addrToFrame(addr);
        if (self.testBit(frame)) {
            self.clearBit(frame);
            self.free_frames += 1;
        }
    }

    /// Convert frame number to physical address
    fn frameToAddr(self: *Self, frame: usize) usize {
        return self.base_addr + (frame << PAGE_SHIFT);
    }

    /// Convert physical address to frame number
    fn addrToFrame(self: *Self, addr: usize) usize {
        return (addr - self.base_addr) >> PAGE_SHIFT;
    }

    /// Mark a frame as allocated in the bitmap
    fn setBit(self: *Self, frame: usize) void {
        const byte_idx = frame >> 3; // frame / 8
        const bit_idx = @as(u3, @truncate(frame & 7)); // frame % 8
        self.bitmap[byte_idx] |= (@as(u8, 1) << bit_idx);
    }

    /// Mark a frame as free in the bitmap
    fn clearBit(self: *Self, frame: usize) void {
        const byte_idx = frame >> 3;
        const bit_idx = @as(u3, @truncate(frame & 7));
        self.bitmap[byte_idx] &= ~(@as(u8, 1) << bit_idx);
    }

    /// Check if a frame is allocated
    fn testBit(self: *Self, frame: usize) bool {
        const byte_idx = frame >> 3;
        const bit_idx = @as(u3, @truncate(frame & 7));
        return (self.bitmap[byte_idx] & (@as(u8, 1) << bit_idx)) != 0;
    }
};
