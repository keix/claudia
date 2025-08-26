// userland/syscalls/io/readdir.zig - Read directory entries
const syscall = @import("syscall");
const abi = @import("abi");

// Directory entry structure (must match kernel)
pub const DirEntry = extern struct {
    name: [256]u8,
    name_len: u8,
    node_type: u8, // 1=FILE, 2=DIRECTORY, 3=DEVICE
    _padding: [6]u8 = undefined, // Ensure proper alignment to 264 bytes
};

comptime {
    // Ensure DirEntry has a consistent size
    if (@sizeOf(DirEntry) != 264) {
        @compileError("DirEntry size must be 264 bytes");
    }
}

pub fn readdir(path: []const u8, entries: []DirEntry) isize {
    return syscall.syscall3(abi.sysno.sys_getdents64, @intFromPtr(path.ptr), @intFromPtr(entries.ptr), entries.len);
}
