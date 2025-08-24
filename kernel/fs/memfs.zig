// kernel/fs/memfs.zig - In-memory filesystem implementation
const std = @import("std");
const defs = @import("abi");
const vfs = @import("vfs.zig");
const file = @import("../file/core.zig");

// Memory file structure
pub const MemFile = struct {
    vnode: *vfs.VNode,
    data: [4096]u8 = undefined, // Fixed size buffer for now
    size: usize = 0,
    pos: usize = 0,
    ref_count: usize = 0,

    pub fn init(node: *vfs.VNode) MemFile {
        return .{
            .vnode = node,
            .ref_count = 1,
        };
    }

    pub fn addRef(self: *MemFile) void {
        self.ref_count += 1;
    }

    pub fn release(self: *MemFile) void {
        if (self.ref_count > 0) {
            self.ref_count -= 1;
        }
    }
};

// File operations for memory files
const MemFileOperations = file.types.FileOperations{
    .read = memFileRead,
    .write = memFileWrite,
    .close = memFileClose,
};

fn memFileRead(f: *file.types.File, buffer: []u8) isize {
    _ = f; // We'll get mem_file from a different approach
    // TODO: Implement proper file to memfile mapping
    return 0;

    // Calculate how much we can read
    const available = if (mem_file.size > mem_file.pos)
        mem_file.size - mem_file.pos
    else
        0;
    const to_read = @min(buffer.len, available);

    if (to_read == 0) return 0;

    // Copy data
    @memcpy(buffer[0..to_read], mem_file.data[mem_file.pos .. mem_file.pos + to_read]);
    mem_file.pos += to_read;

    return @as(isize, @intCast(to_read));
}

fn memFileWrite(f: *file.types.File, data: []const u8) isize {
    const mem_file = @fieldParentPtr(MemFile, "file_ops", f.ops);

    // Calculate how much we can write
    const available = if (mem_file.data.len > mem_file.pos)
        mem_file.data.len - mem_file.pos
    else
        0;
    const to_write = @min(data.len, available);

    if (to_write == 0) return defs.ENOSPC; // No space left

    // Copy data
    @memcpy(mem_file.data[mem_file.pos .. mem_file.pos + to_write], data[0..to_write]);
    mem_file.pos += to_write;

    // Update size if we extended the file
    if (mem_file.pos > mem_file.size) {
        mem_file.size = mem_file.pos;
    }

    // Update VNode size
    mem_file.vnode.size = mem_file.size;

    return @as(isize, @intCast(to_write));
}

fn memFileClose(f: *file.types.File) void {
    const mem_file = @fieldParentPtr(MemFile, "file_ops", f.ops);
    mem_file.release();
}

// Static allocation for memory files (temporary solution)
var mem_files: [32]MemFile = undefined;
var next_mem_file: usize = 0;

// Allocate a new memory file
pub fn allocMemFile(node: *vfs.VNode) ?*MemFile {
    if (next_mem_file >= mem_files.len) return null;

    const mf = &mem_files[next_mem_file];
    next_mem_file += 1;

    mf.* = MemFile.init(node);
    return mf;
}

// Create a file wrapper for a memory file
pub fn createFileWrapper(mem_file: *MemFile) file.types.File {
    return file.types.File.init(.REGULAR, &MemFileOperations);
}
