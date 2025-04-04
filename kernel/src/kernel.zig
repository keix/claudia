const VIDEO_MEMORY: [*]volatile u16 = @as([*]volatile u16, @ptrFromInt(0xB8000));
const COLS = 80;
const ROWS = 25;
const SCREEN_SIZE = COLS * ROWS;

const VgaColor = enum(u8) {
    Black = 0,
    Blue = 1,
    Green = 2,
    Cyan = 3,
    Red = 4,
    Magenta = 5,
    Brown = 6,
    LightGray = 7,
    DarkGray = 8,
    LightBlue = 9,
    LightGreen = 10,
    LightCyan = 11,
    LightRed = 12,
    LightMagenta = 13,
    Yellow = 14,
    White = 15,
};

fn makeVgaAttribute(fg: VgaColor, bg: VgaColor) u8 {
    return @intFromEnum(fg) | (@intFromEnum(bg) << 4);
}

fn clearScreen(attribute: u8) void {
    const entry = @as(u16, ' ') | (@as(u16, attribute) << 8);

    var i: usize = 0;
    while (i < SCREEN_SIZE) : (i += 1) {
        VIDEO_MEMORY[i] = entry;
    }
}

fn printString(str: []const u8, attribute: u8, x: usize, y: usize) void {
    var offset = y * COLS + x;

    for (str) |char| {
        VIDEO_MEMORY[offset] = @as(u16, char) | (@as(u16, attribute) << 8);
        offset += 1;
    }
}

export fn _start() callconv(.C) noreturn {
    clearScreen(makeVgaAttribute(VgaColor.White, VgaColor.Black));

    const message = "32-bit Protected Mode Zig Kernel Loaded Successfully!";
    printString(message, makeVgaAttribute(VgaColor.Cyan, VgaColor.Black), 0, 0);

    while (true) {}

    unreachable;
}
