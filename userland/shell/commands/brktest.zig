// brktest.zig - Test program break (heap) management
const sys = @import("sys");
const utils = @import("shell/utils");

const STDOUT: usize = 1;

fn writeString(str: []const u8) void {
    _ = sys.write(STDOUT, @ptrCast(str.ptr), str.len);
}

fn writeChar(ch: u8) void {
    const buf = [_]u8{ch};
    _ = sys.write(STDOUT, @ptrCast(&buf), 1);
}

fn writeInt(val: usize) void {
    var buf: [32]u8 = undefined;
    const str = utils.intToStr(@intCast(val));
    for (str, 0..) |ch, i| {
        buf[i] = ch;
    }
    writeString(str);
}

fn writeHex(val: usize) void {
    const hex_chars = "0123456789abcdef";
    var buf: [16]u8 = undefined;
    var i: usize = 0;
    var v = val;

    if (v == 0) {
        writeChar('0');
        return;
    }

    while (v > 0 and i < 16) {
        buf[15 - i] = hex_chars[v & 0xF];
        v >>= 4;
        i += 1;
    }

    writeString(buf[16 - i .. 16]);
}

pub fn main(args: *const utils.Args) void {
    _ = args; // No arguments needed
    run();
}

fn run() void {
    writeString("Testing brk/sbrk system calls...\n");

    // Test 1: Get current program break
    const initial_brk = sys.sbrk(0);
    if (initial_brk < 0) {
        writeString("ERROR: Failed to get initial break\n");
        return;
    }
    writeString("Initial program break: 0x");
    writeHex(@intCast(initial_brk));
    writeString("\n");

    // Test 2: Allocate 4096 bytes (1 page)
    const alloc_size: isize = 4096;
    const old_brk = sys.sbrk(alloc_size);
    if (old_brk < 0) {
        writeString("ERROR: Failed to allocate memory\n");
        return;
    }
    writeString("Allocated ");
    writeInt(@intCast(alloc_size));
    writeString(" bytes\n");

    // Test 3: Verify new break
    const new_brk = sys.sbrk(0);
    if (new_brk != old_brk + alloc_size) {
        writeString("ERROR: Break not updated correctly\n");
        writeString("Expected: 0x");
        writeHex(@intCast(old_brk + alloc_size));
        writeString(", Got: 0x");
        writeHex(@intCast(new_brk));
        writeString("\n");
        return;
    }
    writeString("New program break: 0x");
    writeHex(@intCast(new_brk));
    writeString("\n");

    // Test 4: Write to allocated memory
    const mem_ptr = @as([*]u8, @ptrFromInt(@as(usize, @intCast(old_brk))));
    mem_ptr[0] = 'H';
    mem_ptr[1] = 'E';
    mem_ptr[2] = 'A';
    mem_ptr[3] = 'P';
    mem_ptr[4] = 0;

    writeString("Written to heap: ");
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        writeChar(mem_ptr[i]);
    }
    writeString("\n");

    // Test 5: Shrink heap by 2048 bytes
    const shrink_result = sys.sbrk(-2048);
    if (shrink_result < 0) {
        writeString("ERROR: Failed to shrink heap\n");
        return;
    }
    writeString("Shrunk heap by 2048 bytes\n");

    const final_brk = sys.sbrk(0);
    writeString("Final program break: 0x");
    writeHex(@intCast(final_brk));
    writeString("\n");

    // Test 6: Test brk() directly
    const target_brk = initial_brk + 8192;
    const brk_result = sys.brk(@intCast(target_brk));
    if (brk_result != 0) {
        writeString("ERROR: brk() failed\n");
        return;
    }
    writeString("Successfully set break to 0x");
    writeHex(@intCast(target_brk));
    writeString("\n");

    const verify_brk = sys.sbrk(0);
    if (verify_brk != target_brk) {
        writeString("ERROR: brk() didn't set correct value\n");
        return;
    }

    writeString("All brk/sbrk tests passed!\n");
}
