// kernel/file/dirfile.zig - Directory file implementation
const std = @import("std");
const File = @import("core.zig").File;
const FileType = @import("types.zig").FileType;
const FileOperations = @import("core.zig").FileOperations;
const vfs = @import("../fs/vfs.zig");
const defs = @import("abi");

// Directory file structure
pub const DirFile = struct {
    file: File,
    vnode: *vfs.VNode,
    position: usize, // Current read position for getdents
};

// Directory operations
const DirOperations = FileOperations{
    .read = dirRead,
    .write = dirWrite,
    .close = dirClose,
};

// Directory constants
const MAX_FILENAME_LEN = 256;
const MAX_DIRFILES = 16;

// Directory entry structure for getdents64
pub const DirEntry = extern struct {
    d_ino: u64, // Inode number
    d_off: i64, // Offset to next dirent
    d_reclen: u16, // Length of this record
    d_type: u8, // File type
    d_name: [MAX_FILENAME_LEN]u8, // Filename (null-terminated)
};

fn dirRead(file: *File, buffer: []u8) isize {
    // Get DirFile from File pointer using offset calculation
    const dir_file_ptr = @intFromPtr(file) - @offsetOf(DirFile, "file");
    const dir_file = @as(*DirFile, @ptrFromInt(dir_file_ptr));

    // Verify it's a directory
    if (dir_file.vnode.node_type != .DIRECTORY) {
        return defs.ENOTDIR;
    }

    var offset: usize = 0;
    var entry_count: usize = 0;

    // Add . and .. entries first if at beginning
    if (dir_file.position == 0) {
        // . entry
        var entry: DirEntry = undefined;
        entry.d_ino = 1;
        entry.d_type = 2; // DT_DIR
        entry.d_name[0] = '.';
        entry.d_name[1] = 0;
        const name_len: usize = 1;
        entry.d_reclen = @intCast(@sizeOf(DirEntry) - MAX_FILENAME_LEN + name_len + 1);
        entry.d_off = @intCast(offset + entry.d_reclen);

        const entry_size = entry.d_reclen;
        if (offset + entry_size > buffer.len) {
            if (offset == 0) return defs.EINVAL;
            return @intCast(offset);
        }

        const entry_bytes = @as([*]const u8, @ptrCast(&entry))[0..entry_size];
        @memcpy(buffer[offset .. offset + entry_size], entry_bytes);
        offset += entry_size;
        entry_count += 1;
        dir_file.position += 1;
    }

    if (dir_file.position == 1) {
        // .. entry
        var entry: DirEntry = undefined;
        entry.d_ino = 1;
        entry.d_type = 2; // DT_DIR
        entry.d_name[0] = '.';
        entry.d_name[1] = '.';
        entry.d_name[2] = 0;
        const name_len: usize = 2;
        entry.d_reclen = @intCast(@sizeOf(DirEntry) - MAX_FILENAME_LEN + name_len + 1);
        entry.d_off = @intCast(offset + entry.d_reclen);

        const entry_size = entry.d_reclen;
        if (offset + entry_size > buffer.len) {
            if (offset == 0) return defs.EINVAL;
            return @intCast(offset);
        }

        const entry_bytes = @as([*]const u8, @ptrCast(&entry))[0..entry_size];
        @memcpy(buffer[offset .. offset + entry_size], entry_bytes);
        offset += entry_size;
        entry_count += 1;
        dir_file.position += 1;
    }

    // List children
    var child = dir_file.vnode.getChildren();
    var skip_count: usize = if (dir_file.position > 2) dir_file.position - 2 else 0;
    var inode: u64 = 3;

    while (child) |node| : (child = node.next_sibling) {
        // Skip entries based on position
        if (skip_count > 0) {
            skip_count -= 1;
            inode += 1;
            continue;
        }

        var entry: DirEntry = undefined;
        entry.d_ino = inode;
        entry.d_type = switch (node.node_type) {
            .FILE => 1, // DT_REG
            .DIRECTORY => 2, // DT_DIR
            .DEVICE => 3, // DT_CHR
        };

        // Copy name
        const name = node.getName();
        @memcpy(entry.d_name[0..name.len], name);
        entry.d_name[name.len] = 0;

        const name_len = name.len;
        entry.d_reclen = @intCast(@sizeOf(DirEntry) - MAX_FILENAME_LEN + name_len + 1);
        entry.d_off = @intCast(offset + entry.d_reclen);

        const entry_size = entry.d_reclen;
        if (offset + entry_size > buffer.len) {
            if (offset == 0) return defs.EINVAL;
            break;
        }

        const entry_bytes = @as([*]const u8, @ptrCast(&entry))[0..entry_size];
        @memcpy(buffer[offset .. offset + entry_size], entry_bytes);
        offset += entry_size;
        entry_count += 1;
        dir_file.position += 1;
        inode += 1;
    }

    return @intCast(offset);
}

fn dirWrite(file: *File, data: []const u8) isize {
    _ = file;
    _ = data;
    // Directories cannot be written to
    return defs.EISDIR;
}

fn dirClose(file: *File) void {
    // Get DirFile from File pointer using offset calculation
    const dir_file_ptr = @intFromPtr(file) - @offsetOf(DirFile, "file");
    const dir_file = @as(*DirFile, @ptrFromInt(dir_file_ptr));
    // Free the directory file structure
    freeDirFile(dir_file);
}

// Directory file pool (simple static allocation)
var dirfile_pool: [MAX_DIRFILES]DirFile = undefined;
var dirfile_used: [MAX_DIRFILES]bool = [_]bool{false} ** MAX_DIRFILES;

pub fn allocDirFile(vnode: *vfs.VNode) ?*DirFile {
    for (&dirfile_pool, &dirfile_used, 0..) |*df, *used, i| {
        _ = i;
        if (!used.*) {
            used.* = true;
            df.* = DirFile{
                .file = File.init(FileType.DIRECTORY, &DirOperations),
                .vnode = vnode,
                .position = 0,
            };
            df.vnode.addRef();
            return df;
        }
    }
    return null;
}

pub fn freeDirFile(df: *DirFile) void {
    df.vnode.release();
    const index = (@intFromPtr(df) - @intFromPtr(&dirfile_pool)) / @sizeOf(DirFile);
    if (index < dirfile_used.len) {
        dirfile_used[index] = false;
    }
}
