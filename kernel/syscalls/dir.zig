// kernel/syscalls/dir.zig - Directory operations
const vfs = @import("../fs/vfs.zig");
const copy = @import("../user/copy.zig");
const defs = @import("abi");

// Simple directory entry structure
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

// sys_getdents64 implementation (using readdir internally)
pub fn sys_getdents64(fd: usize, dirp: usize, count: usize) isize {
    // For now, we treat fd as path_addr for simplicity
    // TODO: Properly handle file descriptors
    return sys_readdir(fd, dirp, count);
}

// Read directory entries
// Returns number of entries read, or negative error
pub fn sys_readdir(path_addr: usize, entries_addr: usize, max_entries: usize) isize {
    const uart = @import("../driver/uart/core.zig");

    // Copy path from user space
    var path_buf: [256]u8 = undefined;
    const path_len = copy.copyinstr(&path_buf, path_addr) catch return defs.EFAULT;
    const path = path_buf[0..path_len];

    uart.puts("[sys_readdir] Reading directory: '");
    uart.puts(path);
    uart.puts("' (len=");
    uart.putDec(path.len);
    uart.puts(")\n");

    // Check for root directory special case
    if (path.len == 1 and path[0] == '/') {
        uart.puts("[sys_readdir] Special case: root directory\n");
    }

    // Resolve path
    const node = vfs.resolvePath(path) orelse {
        uart.puts("[sys_readdir] Path not found\n");
        return defs.ENOENT;
    };

    uart.puts("[sys_readdir] Found node: '");
    uart.puts(node.getName());
    uart.puts("'\n");

    // Must be a directory
    if (node.node_type != .DIRECTORY) {
        uart.puts("[sys_readdir] Not a directory, type: ");
        uart.putDec(@intFromEnum(node.node_type));
        uart.puts("\n");
        return defs.ENOTDIR;
    }

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

        uart.puts("[sys_readdir] Entry ");
        uart.putDec(idx);
        uart.puts(": ");
        uart.puts(name);
        uart.puts(" (type=");
        uart.putDec(entry.node_type);
        uart.puts(")\n");

        idx += 1;
    }

    // Debug: print size of DirEntry
    uart.puts("[sys_readdir] sizeof(DirEntry) = ");
    uart.putDec(@sizeOf(DirEntry));
    uart.puts("\n");

    // Copy entries to user space in reverse order to show oldest first
    var count: usize = 0;
    while (count < idx) : (count += 1) {
        const entry = &temp_entries[idx - 1 - count];
        const entry_addr = entries_addr + count * @sizeOf(DirEntry);

        // Debug: show what we're copying
        uart.puts("[sys_readdir] Copying entry at offset ");
        uart.putDec(count * @sizeOf(DirEntry));
        uart.puts(", name='");
        const debug_name = entry.name[0..entry.name_len];
        uart.puts(debug_name);
        uart.puts("'\n");

        _ = copy.copyout(entry_addr, std.mem.asBytes(entry)) catch {
            uart.puts("[sys_readdir] copyout failed\n");
            return defs.EFAULT;
        };
    }

    uart.puts("[sys_readdir] Returning ");
    uart.putDec(count);
    uart.puts(" entries\n");

    return @intCast(count);
}

const std = @import("std");
