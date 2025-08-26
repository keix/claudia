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
    // const uart = @import("../driver/uart/core.zig");
    // uart.puts("[sys_write] called with fd=");
    // uart.putDec(fd);
    // uart.puts(", len=");
    // uart.putDec(len);
    // uart.puts("\n");

    const getFile = file_getFile orelse return defs.ENOSYS;
    const writeFile = file_write orelse return defs.ENOSYS;

    const f = getFile(@as(i32, @intCast(fd))) orelse return defs.EBADF;
    var tmp: [256]u8 = undefined;
    var left = len;
    var off: usize = 0;
    var done: usize = 0;

    while (left > 0) {
        const n = if (left > tmp.len) tmp.len else left;
        if (copy.copyin(tmp[0..n], ubuf + off)) |_| {} else |_| return defs.EFAULT;
        // uart.puts("[sys_write] About to call writeFile with ");
        // uart.putDec(n);
        // uart.puts(" bytes\n");
        const w = writeFile(f, tmp[0..n]);
        // uart.puts("[sys_write] writeFile returned: ");
        // uart.putDec(@as(usize, @bitCast(w)));
        // uart.puts("\n");
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
    const getFile = file_getFile orelse return defs.ENOSYS;
    const readFile = file_read orelse return defs.ENOSYS;

    const f = getFile(@as(i32, @intCast(fd))) orelse return defs.EBADF;
    var tmp: [256]u8 = undefined;
    const n = if (len > tmp.len) tmp.len else len;
    const r = readFile(f, tmp[0..n]);
    if (r < 0) return r;
    _ = copy.copyout(ubuf, tmp[0..@as(usize, @intCast(r))]) catch return defs.EFAULT;
    return r;
}

pub fn sys_close(fd: usize) isize {
    const closeFile = file_close orelse return defs.ENOSYS;
    return closeFile(@as(i32, @intCast(fd)));
}

// AT_FDCWD constant for openat
const AT_FDCWD: isize = -100;

pub fn sys_openat(dirfd: usize, pathname: usize, flags: usize, mode: usize) isize {
    const openFile = file_open orelse return defs.ENOSYS;

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
