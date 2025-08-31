// kernel/syscalls/fs.zig - File system syscalls
const defs = @import("abi");
const copy = @import("../user/copy.zig");

// Forward declare file module to avoid circular imports
// These will be set by the dispatcher
var file_getFile: ?*const fn (i32) ?*anyopaque = null;
var file_write: ?*const fn (*anyopaque, []const u8) isize = null;
var file_read: ?*const fn (*anyopaque, []u8) isize = null;
var file_close: ?*const fn (i32) isize = null;
var file_open: ?*const fn ([]const u8, u32, u16) isize = null;

// Helper to get function pointer or return ENOSYS
inline fn requireFn(comptime T: type, ptr: ?T) !T {
    return ptr orelse return error.NotImplemented;
}

// Initialize file system function pointers
pub fn init(
    getFile: *const fn (i32) ?*anyopaque,
    writeFile: *const fn (*anyopaque, []const u8) isize,
    readFile: *const fn (*anyopaque, []u8) isize,
    closeFile: *const fn (i32) isize,
) void {
    file_getFile = getFile;
    file_write = writeFile;
    file_read = readFile;
    file_close = closeFile;
}

// Set open function pointer separately (to avoid changing existing init signature)
pub fn setOpenFn(openFn: *const fn ([]const u8, u32, u16) isize) void {
    file_open = openFn;
}

pub fn sys_write(fd: usize, ubuf: usize, len: usize) isize {
    const getFile = requireFn(@TypeOf(file_getFile.?), file_getFile) catch return defs.ENOSYS;
    const writeFile = requireFn(@TypeOf(file_write.?), file_write) catch return defs.ENOSYS;

    const f = getFile(@as(i32, @intCast(fd))) orelse return defs.EBADF;
    var tmp: [256]u8 = undefined;
    var left = len;
    var off: usize = 0;
    var done: usize = 0;

    while (left > 0) {
        const n = if (left > tmp.len) tmp.len else left;
        if (copy.copyin(tmp[0..n], ubuf + off)) |_| {} else |_| return defs.EFAULT;
        const w = writeFile(f, tmp[0..n]);
        if (w < 0) return w;
        const written = @as(usize, @intCast(w));
        done += written;

        // Check for zero write to prevent infinite loop
        if (written == 0) {
            break;
        }

        left -= written;
        off += written;
    }

    return @as(isize, @intCast(done));
}

pub fn sys_read(fd: usize, ubuf: usize, len: usize) isize {
    const getFile = requireFn(@TypeOf(file_getFile.?), file_getFile) catch return defs.ENOSYS;
    const readFile = requireFn(@TypeOf(file_read.?), file_read) catch return defs.ENOSYS;

    const f = getFile(@as(i32, @intCast(fd))) orelse return defs.EBADF;

    // Use a larger temporary buffer for reading
    var tmp: [1024]u8 = undefined;
    var left = len;
    var off: usize = 0;
    var done: usize = 0;

    while (left > 0) {
        const n = if (left > tmp.len) tmp.len else left;
        const r = readFile(f, tmp[0..n]);
        if (r < 0) return r;
        if (r == 0) break; // EOF

        const read_bytes = @as(usize, @intCast(r));
        _ = copy.copyout(ubuf + off, tmp[0..read_bytes]) catch return defs.EFAULT;

        done += read_bytes;
        left -= read_bytes;
        off += read_bytes;

        // If we read less than requested, we've hit EOF
        if (read_bytes < n) break;
    }

    return @as(isize, @intCast(done));
}

pub fn sys_close(fd: usize) isize {
    const closeFile = requireFn(@TypeOf(file_close.?), file_close) catch return defs.ENOSYS;
    return closeFile(@as(i32, @intCast(fd)));
}

// AT_FDCWD constant for openat
const AT_FDCWD: isize = -100;

pub fn sys_openat(dirfd: usize, pathname: usize, flags: usize, mode: usize) isize {
    const openFile = requireFn(@TypeOf(file_open.?), file_open) catch return defs.ENOSYS;

    // For now, only support AT_FDCWD (ignore dirfd)
    const fd = @as(isize, @bitCast(dirfd));
    if (fd != AT_FDCWD) {
        // TODO: Support relative paths from directory fd
        return defs.ENOSYS;
    }

    // Copy pathname from user space
    var path_buf: [256]u8 = undefined;
    const path_len = copy.copyinstr(&path_buf, pathname) catch return defs.EFAULT;

    // Convert flags and mode to appropriate types
    const open_flags = @as(u32, @truncate(flags));
    const open_mode = @as(u16, @truncate(mode));

    // Call the open function
    return openFile(path_buf[0..path_len], open_flags, open_mode);
}
