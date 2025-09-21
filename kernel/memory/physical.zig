const types = @import("types.zig");
const uart = @import("../driver/uart/core.zig");

pub const PAGE_SIZE = types.PAGE_SIZE;
pub const PAGE_SHIFT = types.PAGE_SHIFT;

// Protected page table addresses
const PROTECTED_PAGE_TABLE_1 = 0x802bf000;
const PROTECTED_PAGE_TABLE_2 = 0x802cf000;

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
        // Never free active page tables
        if (addr == PROTECTED_PAGE_TABLE_1 or addr == PROTECTED_PAGE_TABLE_2) {
            return;
        }

        // Validate address
        if (addr < self.base_addr or addr >= self.base_addr + (self.total_frames << PAGE_SHIFT)) {
            return;
        }
        if ((addr & (PAGE_SIZE - 1)) != 0) {
            return;
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
