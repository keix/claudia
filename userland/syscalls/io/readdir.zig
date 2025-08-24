// userland/syscalls/io/readdir.zig - Read directory entries
const syscall = @import("syscall");
const abi = @import("abi");

// Directory entry structure (must match kernel)
pub const DirEntry = struct {
    name: [256]u8,
    name_len: u8,
    node_type: u8, // 1=FILE, 2=DIRECTORY, 3=DEVICE
};

pub fn readdir(path: []const u8, entries: []DirEntry) isize {
    return syscall.syscall3(abi.sysno.sys_getdents64, @intFromPtr(path.ptr), @intFromPtr(entries.ptr), entries.len);
}
