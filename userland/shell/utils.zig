// Shell utility functions (string operations, I/O, etc.)
const sys = @import("sys");

const STDIN: usize = 0;
const STDOUT: usize = 1;

// I/O functions
pub fn writeStr(str: []const u8) void {
    _ = sys.write(STDOUT, @ptrCast(str.ptr), str.len);
}

pub fn readChar(buf: *u8) isize {
    return sys.read(STDIN, @ptrCast(buf), 1);
}

pub fn readLine(buf: []u8) isize {
    return sys.read(STDIN, @ptrCast(buf.ptr), buf.len);
}

// Maximum number of arguments
pub const MAX_ARGS: usize = 16;

// Command arguments structure
pub const Args = struct {
    argc: usize,
    argv: [MAX_ARGS][]const u8,

    pub fn init() Args {
        return Args{
            .argc = 0,
            .argv = undefined,
        };
    }
};

// String utility functions
pub fn strEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (ca != cb) return false;
    }
    return true;
}

pub fn trimLeadingWhitespace(input: []const u8) []const u8 {
    var start: usize = 0;
    while (start < input.len and input[start] == ' ') {
        start += 1;
    }
    return input[start..];
}

pub fn parseCommandLine(buffer: []const u8, pos: usize) []const u8 {
    // Skip leading whitespace
    var start: usize = 0;
    while (start < pos and buffer[start] == ' ') start += 1;

    if (start >= pos) return ""; // Empty command

    // Find the end, excluding trailing whitespace and control characters
    var end: usize = pos;
    while (end > start and (buffer[end - 1] == ' ' or buffer[end - 1] == '\n' or buffer[end - 1] == '\r' or buffer[end - 1] == 0)) {
        end -= 1;
    }

    if (end <= start) return ""; // Empty after trimming

    return buffer[start..end];
}

// Parse command line into argc/argv
pub fn parseArgs(cmdline: []const u8, args: *Args) void {
    args.argc = 0;

    var i: usize = 0;
    while (i < cmdline.len and args.argc < MAX_ARGS) {
        // Skip whitespace
        while (i < cmdline.len and cmdline[i] == ' ') {
            i += 1;
        }

        if (i >= cmdline.len) break;

        // Start of argument
        const start = i;

        // Find end of argument (simple parsing - no quotes for now)
        while (i < cmdline.len and cmdline[i] != ' ') {
            i += 1;
        }

        // Store argument
        args.argv[args.argc] = cmdline[start..i];
        args.argc += 1;
    }
}

// Convert integer to string (simple implementation)
var int_buf: [12]u8 = undefined;
pub fn intToStr(value: i32) []const u8 {
    if (value == 0) {
        int_buf[0] = '0';
        return int_buf[0..1];
    }

    var val = value;
    var negative = false;
    if (val < 0) {
        negative = true;
        val = -val;
    }

    var pos: usize = int_buf.len;
    while (val > 0) {
        pos -= 1;
        int_buf[pos] = @as(u8, '0' + @as(u8, @intCast(@mod(val, 10))));
        val = @divTrunc(val, 10);
    }

    if (negative) {
        pos -= 1;
        int_buf[pos] = '-';
    }

    return int_buf[pos..];
}

// Copy string to buffer
pub fn strCopy(dest: []u8, src: []const u8) void {
    const len = @min(dest.len - 1, src.len);
    for (0..len) |i| {
        dest[i] = src[i];
    }
    dest[len] = 0;
}

// Get string from null-terminated buffer
pub fn strFromBuf(buf: []const u8) []const u8 {
    var len: usize = 0;
    while (len < buf.len and buf[len] != 0) {
        len += 1;
    }
    return buf[0..len];
}
