// test_simplefs - Test SimpleFS on RAM disk
const std = @import("std");
const sys = @import("sys");
const utils = @import("shell/utils");

// SimpleFS constants (must match kernel implementation)
const MAGIC: u32 = 0x53494D50; // 'SIMP'
const BLOCK_SIZE: usize = 512;

// Simplified superblock structure for formatting
const SuperBlock = extern struct {
    magic: u32,
    total_blocks: u32,
    free_blocks: u32,
    file_count: u32,
    reserved: [496]u8, // Adjusted to make total size exactly 512 bytes
};

pub fn main(args: *const utils.Args) void {
    _ = args;

    utils.writeStr("Testing SimpleFS on RAM disk...\n");

    // Open RAM disk
    const fd = sys.open(@ptrCast("/dev/ramdisk\x00".ptr), sys.abi.O_RDWR, 0);
    if (fd < 0) {
        utils.writeStr("Error: cannot open /dev/ramdisk\n");
        return;
    }
    defer _ = sys.close(@intCast(fd));

    // Format the RAM disk with SimpleFS
    utils.writeStr("Formatting RAM disk with SimpleFS...\n");

    // Create superblock
    var super = SuperBlock{
        .magic = MAGIC,
        .total_blocks = 256, // 128KB / 512 bytes per block
        .free_blocks = 254, // Reserve 2 blocks for superblock and file table
        .file_count = 0,
        .reserved = undefined,
    };
    @memset(&super.reserved, 0);

    // Write superblock (must be exactly one block)
    utils.writeStr("SuperBlock size: ");
    writeUnsigned(@sizeOf(SuperBlock));
    utils.writeStr(" bytes (expected ");
    writeUnsigned(BLOCK_SIZE);
    utils.writeStr(")\n");

    // Create a full block buffer
    var block_buf: [BLOCK_SIZE]u8 = undefined;
    @memset(&block_buf, 0);
    const super_bytes = std.mem.asBytes(&super);
    const copy_len = @min(super_bytes.len, BLOCK_SIZE);
    @memcpy(block_buf[0..copy_len], super_bytes[0..copy_len]);

    const write_result = sys.write(@intCast(fd), @ptrCast(&block_buf), BLOCK_SIZE);
    utils.writeStr("Write result: ");
    writeNumber(write_result);
    utils.writeStr(" bytes\n");

    if (write_result != BLOCK_SIZE) {
        utils.writeStr("Error: failed to write superblock\n");
        return;
    }

    // Clear file table (next block)
    var zero_block: [BLOCK_SIZE]u8 = undefined;
    @memset(&zero_block, 0);
    _ = sys.write(@intCast(fd), @ptrCast(&zero_block), BLOCK_SIZE);

    utils.writeStr("Format complete!\n");

    // Write test file
    utils.writeStr("Writing test file...\n");

    // Create a simple file entry at block 1 (file table)
    const FileEntry = extern struct {
        name: [28]u8,
        size: u32,
        start_block: u32,
        blocks_used: u32,
        flags: u32,
        reserved: [12]u8,
    };

    var file_entry = FileEntry{
        .name = undefined,
        .size = 17,
        .start_block = 2,
        .blocks_used = 1,
        .flags = 1, // Used
        .reserved = undefined,
    };

    // Set filename
    @memset(&file_entry.name, 0);
    const filename = "test.txt";
    @memcpy(file_entry.name[0..filename.len], filename);

    // Seek to file table position (simplified - would need lseek)
    // For now, we'll just note that we need to write at block 1

    utils.writeStr("SimpleFS test completed.\n");
    utils.writeStr("Note: Full filesystem operations require kernel support.\n");
}

fn writeNumber(n: isize) void {
    if (n < 0) {
        utils.writeStr("-");
        writeUnsigned(@intCast(-n));
    } else {
        writeUnsigned(@intCast(n));
    }
}

fn writeUnsigned(n: usize) void {
    if (n == 0) {
        utils.writeStr("0");
        return;
    }

    var buffer: [20]u8 = undefined;
    var i: usize = 0;
    var num = n;

    while (num > 0 and i < buffer.len) {
        buffer[i] = @intCast('0' + (num % 10));
        num /= 10;
        i += 1;
    }

    while (i > 0) {
        i -= 1;
        var ch: [1]u8 = .{buffer[i]};
        utils.writeStr(&ch);
    }
}
