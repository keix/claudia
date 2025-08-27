// kernel/syscalls/path.zig - Path related system calls
const std = @import("std");
const defs = @import("abi");
const proc = @import("../process/core.zig");
const copy = @import("../user/copy.zig");
const vfs = @import("../fs/vfs.zig");

// sys_getcwd implementation
pub fn sys_getcwd(buf_addr: usize, size: usize) isize {
    const current = proc.current_process orelse return defs.ESRCH;

    // Check if buffer size is sufficient
    if (size == 0) return defs.EINVAL;
    if (current.cwd_len + 1 > size) return defs.ERANGE;

    // Copy current working directory to user buffer
    _ = copy.copyout(buf_addr, current.cwd[0 .. current.cwd_len + 1]) catch return defs.EFAULT;

    return @as(isize, @intCast(current.cwd_len));
}

// sys_chdir implementation
pub fn sys_chdir(path_addr: usize) isize {
    const current = proc.current_process orelse return defs.ESRCH;

    // Copy path from user space
    var path_buf: [256]u8 = undefined;
    const path_len = copy.copyinstr(&path_buf, path_addr) catch return defs.EFAULT;

    if (path_len == 0) return defs.EINVAL;

    const path = path_buf[0..path_len];

    // Build absolute path
    var new_cwd: [256]u8 = undefined;
    var new_len: usize = 0;

    if (path[0] == '/') {
        // Absolute path - just check if it exists
        if (path_len >= new_cwd.len) return defs.ENAMETOOLONG;
        @memcpy(new_cwd[0..path_len], path);
        new_len = path_len;
    } else {
        // Relative path - need to resolve from current directory
        // First, check if the relative path exists from current location
        var check_path: [256]u8 = undefined;
        var check_len: usize = 0;

        // Build full path for checking
        @memcpy(check_path[0..current.cwd_len], current.cwd[0..current.cwd_len]);
        check_len = current.cwd_len;

        // Add separator if needed
        if (current.cwd_len > 1 and current.cwd[current.cwd_len - 1] != '/') {
            check_path[check_len] = '/';
            check_len += 1;
        }

        // Append relative path
        @memcpy(check_path[check_len .. check_len + path_len], path);
        check_len += path_len;

        // Null terminate for VFS
        check_path[check_len] = 0;

        // Check if this path exists
        const check_node = vfs.resolvePath(check_path[0..check_len]) orelse return defs.ENOENT;
        if (check_node.node_type != .DIRECTORY) return defs.ENOTDIR;

        // Path is valid, use it
        @memcpy(new_cwd[0..check_len], check_path[0..check_len]);
        new_len = check_len;
    }

    // Normalize the path (remove trailing slash except for root)
    if (new_len > 1 and new_cwd[new_len - 1] == '/') {
        new_len -= 1;
    }

    // Update process's current directory
    @memcpy(current.cwd[0..new_len], new_cwd[0..new_len]);
    current.cwd[new_len] = 0; // Null terminate
    current.cwd_len = new_len;

    return 0;
}
