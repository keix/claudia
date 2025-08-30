const std = @import("std");
const types = @import("types.zig");
const memory = @import("../memory/core.zig");

// Inode structure
pub const Inode = struct {
    inum: u32, // Inode number
    ref_count: u32, // Reference count
    valid: bool, // Inode has been read from disk

    // Metadata
    type: types.FileType,
    size: u64,
    mode: u16, // Permissions
    uid: u32, // User ID
    gid: u32, // Group ID

    // Timestamps (Unix timestamps)
    atime: i64, // Access time
    mtime: i64, // Modification time
    ctime: i64, // Change time

    // Data blocks (simple direct blocks for now)
    direct: [DIRECT_BLOCKS]u32, // Direct block pointers
    indirect: u32, // Single indirect
    double_indirect: u32, // Double indirect

    // Operations interface
    ops: *const InodeOperations,

    pub fn init(inum: u32, file_type: types.FileType, ops: *const InodeOperations) Inode {
        return Inode{
            .inum = inum,
            .ref_count = 1,
            .valid = false,
            .type = file_type,
            .size = 0,
            .mode = 0o644, // Default permissions: rw-r--r--
            .uid = 0,
            .gid = 0,
            .atime = 0,
            .mtime = 0,
            .ctime = 0,
            .direct = [_]u32{0} ** DIRECT_BLOCKS,
            .indirect = 0,
            .double_indirect = 0,
            .ops = ops,
        };
    }

    pub fn ref(self: *Inode) void {
        self.ref_count += 1;
    }

    pub fn unref(self: *Inode) void {
        if (self.ref_count > 0) {
            self.ref_count -= 1;
            if (self.ref_count == 0) {
                // Automatically free when ref_count reaches 0
                InodeTable.freeInode(self);
            }
        }
    }
};

// Inode operations interface
pub const InodeOperations = struct {
    read: *const fn (*Inode, []u8, u64) isize,
    write: *const fn (*Inode, []const u8, u64) isize,
    truncate: *const fn (*Inode, u64) anyerror!void,
    lookup: ?*const fn (*Inode, []const u8) ?*Inode, // For directories
};

// Inode table constants
const MAX_INODES = 64;
const DIRECT_BLOCKS = 12;

// Simple inode table (in-memory for now)
const InodeTable = struct {
    inodes: [MAX_INODES]?*Inode, // Pointer array for stable references
    free_list: [MAX_INODES]bool, // Free slot management
    next_inum: u32,

    var instance: InodeTable = .{
        .inodes = [_]?*Inode{null} ** MAX_INODES,
        .free_list = [_]bool{true} ** MAX_INODES,
        .next_inum = 1,
    };

    pub fn alloc(file_type: types.FileType, ops: *const InodeOperations) ?*Inode {
        // Find free slot
        for (0..instance.free_list.len) |i| {
            if (instance.free_list[i]) {
                // Allocate memory for new inode
                const frame = memory.allocFrame() orelse return null;
                const new_inode = @as(*Inode, @ptrFromInt(frame));
                new_inode.* = Inode.init(instance.next_inum, file_type, ops);

                instance.inodes[i] = new_inode;
                instance.free_list[i] = false;
                instance.next_inum += 1;

                return new_inode;
            }
        }
        return null; // No free slots
    }

    fn freeInode(inode: *Inode) void {
        for (0..instance.inodes.len) |i| {
            if (instance.inodes[i]) |existing| {
                if (existing == inode) {
                    // Free the memory frame
                    memory.freeFrame(@intFromPtr(existing));
                    instance.inodes[i] = null;
                    instance.free_list[i] = true;
                    break;
                }
            }
        }
    }

    // Public free should only decrement ref_count
    pub fn free(inode: *Inode) void {
        inode.unref();
    }
};

// Public API
pub const alloc = InodeTable.alloc;
pub const free = InodeTable.free;
