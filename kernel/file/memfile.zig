// Memory-based file implementation
const std = @import("std");
const File = @import("core.zig").File;
const FileOperations = @import("core.zig").FileOperations;
const vfs = @import("../fs/vfs.zig");
const defs = @import("abi");

// Memory file structure - associates a File with a VNode
pub const MemFile = struct {
    file: File,
    vnode: *vfs.VNode,
    position: usize,
    
    pub fn init(vnode: *vfs.VNode) MemFile {
        return .{
            .file = File.init(.REGULAR, &MemFileOperations),
            .vnode = vnode,
            .position = 0,
        };
    }
};

// Memory file operations
const MemFileOperations = FileOperations{
    .read = memRead,
    .write = memWrite,
    .close = memClose,
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
    const copy = @import("../user/copy.zig");
    const user_addr = @intFromPtr(buffer.ptr);
    _ = copy.copyout(user_addr, vnode.data[mem_file.position..mem_file.position + to_read]) catch return defs.EFAULT;
    
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
    @memcpy(vnode.data[mem_file.position..mem_file.position + to_write], data[0..to_write]);
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
    // Decrement VNode reference count
    mem_file.vnode.release();
    // Mark as free
    freeMemFile(mem_file);
}

// Pool of memory files (simple static allocation for now)
var mem_file_pool: [32]MemFile = undefined;
var mem_file_used: [32]bool = [_]bool{false} ** 32;

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