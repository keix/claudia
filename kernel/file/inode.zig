const std = @import("std");
const types = @import("types.zig");

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
    direct: [12]u32, // Direct block pointers
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
            .direct = [_]u32{0} ** 12,
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

// Simple inode table (in-memory for now)
const InodeTable = struct {
    inodes: [64]?Inode,
    next_inum: u32,

    var instance: InodeTable = .{
        .inodes = [_]?Inode{null} ** 64,
        .next_inum = 1,
    };

    pub fn alloc(file_type: types.FileType, ops: *const InodeOperations) ?*Inode {
        for (0..instance.inodes.len) |i| {
            if (instance.inodes[i] == null) {
                instance.inodes[i] = Inode.init(instance.next_inum, file_type, ops);
                instance.next_inum += 1;
                return &instance.inodes[i].?;
            }
        }
        return null; // No free inodes
    }

    pub fn free(inode: *Inode) void {
        for (0..instance.inodes.len) |i| {
            if (instance.inodes[i]) |*existing| {
                if (existing.inum == inode.inum) {
                    instance.inodes[i] = null;
                    break;
                }
            }
        }
    }
};

// Public API
pub const alloc = InodeTable.alloc;
pub const free = InodeTable.free;
