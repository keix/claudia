// kernel/syscalls/dir.zig - Directory operations
const vfs = @import("../fs/vfs.zig");
const copy = @import("../user/copy.zig");
const defs = @import("abi");

// Simple directory entry structure
pub const DirEntry = struct {
    name: [256]u8,
    name_len: u8,
    node_type: u8, // 1=FILE, 2=DIRECTORY, 3=DEVICE
};

// sys_getdents64 implementation (using readdir internally)
pub fn sys_getdents64(fd: usize, dirp: usize, count: usize) isize {
    // For now, we treat fd as path_addr for simplicity
    // TODO: Properly handle file descriptors
    return sys_readdir(fd, dirp, count);
}

// Read directory entries
// Returns number of entries read, or negative error
pub fn sys_readdir(path_addr: usize, entries_addr: usize, max_entries: usize) isize {
    // Copy path from user space
    var path_buf: [256]u8 = undefined;
    const path_len = copy.copyinstr(&path_buf, path_addr) catch return defs.EFAULT;
    const path = path_buf[0..path_len];

    // Resolve path
    const node = vfs.resolvePath(path) orelse return defs.ENOENT;

    // Must be a directory
    if (node.node_type != .DIRECTORY) return defs.ENOTDIR;

    // First, count entries to reverse the order (since they're added in reverse)
    var total_count: usize = 0;
    var temp = node.getChildren();
    while (temp) |_| : (temp = temp.?.next_sibling) {
        total_count += 1;
    }

    // Create a temporary array to store entries in reverse order
    var temp_entries: [32]DirEntry = undefined;
    var current = node.getChildren();
    var idx: usize = 0;

    // Collect entries
    while (current) |child| : (current = child.next_sibling) {
        if (idx >= max_entries or idx >= temp_entries.len) break;

        // Create directory entry
        var entry = &temp_entries[idx];
        entry.* = DirEntry{
            .name = undefined,
            .name_len = 0,
            .node_type = @intFromEnum(child.node_type),
        };

        // Copy name
        const name = child.getName();
        const copy_len = @min(name.len, entry.name.len - 1);
        @memcpy(entry.name[0..copy_len], name[0..copy_len]);
        entry.name[copy_len] = 0;
        entry.name_len = @intCast(copy_len);

        idx += 1;
    }

    // Copy entries to user space in reverse order to show oldest first
    var count: usize = 0;
    while (count < idx) : (count += 1) {
        const entry = &temp_entries[idx - 1 - count];
        const entry_addr = entries_addr + count * @sizeOf(DirEntry);
        _ = copy.copyout(entry_addr, std.mem.asBytes(entry)) catch return defs.EFAULT;
    }

    return @intCast(count);
}

const std = @import("std");
