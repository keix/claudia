// kernel/syscalls/fs.zig - File system syscalls
const defs = @import("abi");
const copy = @import("../user/copy.zig");

// Forward declare file module to avoid circular imports
// These will be set by the dispatcher
var file_getFile: ?*const fn (i32) ?*anyopaque = null;
var file_write: ?*const fn (*anyopaque, []const u8) isize = null;
var file_read: ?*const fn (*anyopaque, []u8) isize = null;
var file_close: ?*const fn (i32) isize = null;

// Initialize file system function pointers
pub fn init(getFile: *const fn (i32) ?*anyopaque, writeFile: *const fn (*anyopaque, []const u8) isize, readFile: *const fn (*anyopaque, []u8) isize, closeFile: *const fn (i32) isize) void {
    file_getFile = getFile;
    file_write = writeFile;
    file_read = readFile;
    file_close = closeFile;
}

pub fn sys_write(fd: usize, ubuf: usize, len: usize) isize {
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
        const w = writeFile(f, tmp[0..n]);
        if (w < 0) return w;
        done += @as(usize, @intCast(w));
        left -= n;
        off += n;
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
