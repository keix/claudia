// Memory-based file implementation
const std = @import("std");
const File = @import("core.zig").File;
const FileOperations = @import("core.zig").FileOperations;
const vfs = @import("../fs/vfs.zig");
const defs = @import("abi");
const copy = @import("../user/copy.zig");
const core = @import("core.zig");

// Memory file structure - associates a File with a VNode
pub const MemFile = struct {
    file: File,
    vnode: *vfs.VNode,
    position: usize,

    pub fn init(vnode: *vfs.VNode) MemFile {
        var mf = MemFile{
            .file = File.init(.REGULAR, &MemFileOperations),
            .vnode = vnode,
            .position = 0,
        };

        // Create a pseudo-inode for the file with metadata from VNode
        const inode = core.allocInode(.REGULAR, &DummyInodeOps);
        if (inode) |i| {
            i.size = vnode.data_size;
            i.mode = 0o644; // Default file permissions
            // Generate a pseudo inode number based on file position in VFS
            // TODO: Implement proper inode number generation to avoid collisions
            i.inum = @as(u32, @truncate(@intFromPtr(vnode)));
            mf.file.inode = i;
        }

        return mf;
    }

    pub fn lseek(self: *MemFile, offset: i64, whence: u32) isize {
        const new_pos = switch (whence) {
            0 => offset, // SEEK_SET
            1 => @as(i64, @intCast(self.position)) + offset, // SEEK_CUR
            2 => @as(i64, @intCast(self.vnode.data_size)) + offset, // SEEK_END
            else => return defs.EINVAL,
        };

        // Check bounds
        if (new_pos < 0) return defs.EINVAL;

        self.position = @as(usize, @intCast(new_pos));
        return @as(isize, @intCast(self.position));
    }
};

// Dummy inode operations for memory files
// VNode currently handles actual file operations, while Inode exists only
// for metadata access (e.g., fstat). These dummy operations ensure the interface
// is satisfied but delegate actual I/O to VNode through MemFile operations.
const DummyInodeOps = core.InodeOperations{
    .read = dummyRead,
    .write = dummyWrite,
    .truncate = dummyTruncate,
    .lookup = null,
};

fn dummyRead(inode: *core.Inode, buffer: []u8, offset: u64) isize {
    _ = inode;
    _ = buffer;
    _ = offset;
    return defs.ENOSYS;
}

fn dummyWrite(inode: *core.Inode, data: []const u8, offset: u64) isize {
    _ = inode;
    _ = data;
    _ = offset;
    return defs.ENOSYS;
}

fn dummyTruncate(inode: *core.Inode, size: u64) anyerror!void {
    _ = inode;
    _ = size;
    return error.NotSupported;
}

// Memory file operations
const MemFileOperations = FileOperations{
    .read = memRead,
    .write = memWrite,
    .close = memClose,
    .lseek = memLseek,
};

fn memRead(file: *File, buffer: []u8) isize {
    // Get MemFile from File pointer
    const mem_file_ptr = @intFromPtr(file) - @offsetOf(MemFile, "file");
    const mem_file = @as(*MemFile, @ptrFromInt(mem_file_ptr));
    const vnode = mem_file.vnode;

    // Calculate how much we can read
    const available = if (vnode.data_size > mem_file.position)
        vnode.data_size - mem_file.position
    else
        0;
    const to_read = @min(buffer.len, available);

    if (to_read == 0) return 0; // EOF

    // Copy data from VNode's buffer
    const user_addr = @intFromPtr(buffer.ptr);
    _ = copy.copyout(user_addr, vnode.data[mem_file.position .. mem_file.position + to_read]) catch return defs.EFAULT;

    mem_file.position += to_read;
    return @as(isize, @intCast(to_read));
}

fn memWrite(file: *File, data: []const u8) isize {
    // Get MemFile from File pointer
    const mem_file_ptr = @intFromPtr(file) - @offsetOf(MemFile, "file");
    const mem_file = @as(*MemFile, @ptrFromInt(mem_file_ptr));
    const vnode = mem_file.vnode;

    // Calculate how much we can write
    const available = if (vnode.data.len > mem_file.position)
        vnode.data.len - mem_file.position
    else
        0;
    const to_write = @min(data.len, available);

    if (to_write == 0) return defs.ENOSPC; // No space left

    // Copy data to VNode's buffer
    @memcpy(vnode.data[mem_file.position .. mem_file.position + to_write], data[0..to_write]);
    mem_file.position += to_write;

    // Update file size if we extended it
    if (mem_file.position > vnode.data_size) {
        vnode.data_size = mem_file.position;
    }

    return @as(isize, @intCast(to_write));
}

fn memClose(file: *File) void {
    // Get MemFile from File pointer
    const mem_file_ptr = @intFromPtr(file) - @offsetOf(MemFile, "file");
    const mem_file = @as(*MemFile, @ptrFromInt(mem_file_ptr));

    // Free the inode if allocated
    if (file.inode) |inode| {
        core.freeInode(inode);
    }
    // Decrement VNode reference count
    mem_file.vnode.release();
    // Mark as free
    freeMemFile(mem_file);
}

fn memLseek(file: *File, offset: i64, whence: u32) isize {
    // Get MemFile from File pointer
    const mem_file_ptr = @intFromPtr(file) - @offsetOf(MemFile, "file");
    const mem_file = @as(*MemFile, @ptrFromInt(mem_file_ptr));
    return mem_file.lseek(offset, whence);
}

// Memory file pool constants
const MAX_MEMFILES = 32;

// Pool of memory files (simple static allocation for now)
var mem_file_pool: [MAX_MEMFILES]MemFile = undefined;
var mem_file_used: [MAX_MEMFILES]bool = [_]bool{false} ** MAX_MEMFILES;

pub fn allocMemFile(vnode: *vfs.VNode) ?*MemFile {
    for (&mem_file_pool, 0..) |*mf, i| {
        if (!mem_file_used[i]) {
            mem_file_used[i] = true;
            mf.* = MemFile.init(vnode);
            vnode.addRef(); // Increment reference count
            return mf;
        }
    }
    return null; // No free slots
}

pub fn freeMemFile(mem_file: *MemFile) void {
    const index = (@intFromPtr(mem_file) - @intFromPtr(&mem_file_pool)) / @sizeOf(MemFile);
    if (index < mem_file_pool.len) {
        mem_file_used[index] = false;
    }
}
