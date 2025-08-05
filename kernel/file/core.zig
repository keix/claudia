// File abstraction for Claudia kernel
// Provides POSIX-like file interface with device drivers

const std = @import("std");
const uart = @import("../driver/uart.zig");

// Import submodules
pub const types = @import("types.zig");
const inode = @import("inode.zig");

// Re-export common types
pub const FD = types.FD;
pub const FileType = types.FileType;
pub const Inode = inode.Inode;
pub const InodeOperations = inode.InodeOperations;

// File operations function pointers
pub const FileOperations = struct {
    read: *const fn (*File, []u8) isize,
    write: *const fn (*File, []const u8) isize,
    close: *const fn (*File) void,
};

// File structure
pub const File = struct {
    type: types.FileType,
    operations: *const FileOperations,
    ref_count: u32,
    flags: u32,

    // Device-specific data
    device_data: ?*anyopaque,

    // Associated inode (optional for device files)
    inode: ?*Inode,

    pub fn init(file_type: types.FileType, ops: *const FileOperations) File {
        return File{
            .type = file_type,
            .operations = ops,
            .ref_count = 1,
            .flags = 0,
            .device_data = null,
            .inode = null,
        };
    }

    pub fn initWithInode(inode_ptr: *Inode, ops: *const FileOperations) File {
        return File{
            .type = inode_ptr.type,
            .operations = ops,
            .ref_count = 1,
            .flags = 0,
            .device_data = null,
            .inode = inode_ptr,
        };
    }

    pub fn read(self: *File, buffer: []u8) isize {
        return self.operations.read(self, buffer);
    }

    pub fn write(self: *File, data: []const u8) isize {
        return self.operations.write(self, data);
    }

    pub fn close(self: *File) void {
        if (self.ref_count > 0) {
            self.ref_count -= 1;
            if (self.ref_count == 0) {
                self.operations.close(self);
            }
        }
    }

    pub fn addRef(self: *File) void {
        self.ref_count += 1;
    }
};

// Console device operations (stdout/stderr)
const ConsoleOperations = FileOperations{
    .read = consoleRead,
    .write = consoleWrite,
    .close = consoleClose,
};

fn consoleRead(file: *File, buffer: []u8) isize {
    _ = file;
    _ = buffer;
    // Console read not implemented (would need keyboard input)
    return -1; // ENOSYS
}

fn consoleWrite(file: *File, data: []const u8) isize {
    _ = file;
    // Write to UART console
    for (data) |byte| {
        uart.putc(byte);
    }
    return @as(isize, @intCast(data.len));
}

fn consoleClose(file: *File) void {
    _ = file;
    // Console files don't need cleanup
}

// Standard file descriptors
const MAX_FDS = 256;
var file_table: [MAX_FDS]?*File = [_]?*File{null} ** MAX_FDS;

// Console file instances
var console_file = File.init(.DEVICE, &ConsoleOperations);

// File descriptor management
pub const FileTable = struct {
    pub fn init() void {
        uart.debug("Initializing file system\n");

        // Initialize standard file descriptors
        // fd 0: stdin (not implemented yet)
        file_table[0] = null;

        // fd 1: stdout -> console (UART)
        file_table[1] = &console_file;

        // fd 2: stderr -> console (UART)
        file_table[2] = &console_file;
        console_file.addRef(); // Two references (stdout + stderr)

        uart.debug("Standard file descriptors initialized\n");
    }

    pub fn getFile(fd: FD) ?*File {
        if (fd < 0 or fd >= MAX_FDS) {
            return null;
        }
        return file_table[@as(usize, @intCast(fd))];
    }

    pub fn allocFd(file: *File) ?FD {
        // Start from 3 (after stdin/stdout/stderr)
        for (3..MAX_FDS) |i| {
            if (file_table[i] == null) {
                file_table[i] = file;
                file.addRef();
                return @as(FD, @intCast(i));
            }
        }
        return null; // No free file descriptors
    }

    pub fn closeFd(fd: FD) void {
        if (fd < 0 or fd >= MAX_FDS) {
            return;
        }

        const idx = @as(usize, @intCast(fd));
        if (file_table[idx]) |file| {
            file.close();
            file_table[idx] = null;
        }
    }

    // System call implementations
    pub fn sysRead(fd: FD, buffer: []u8) isize {
        if (getFile(fd)) |file| {
            return file.read(buffer);
        }
        return -9; // EBADF - bad file descriptor
    }

    pub fn sysWrite(fd: FD, data: []const u8) isize {
        if (getFile(fd)) |file| {
            return file.write(data);
        }
        return -9; // EBADF - bad file descriptor
    }

    pub fn sysClose(fd: FD) isize {
        if (fd < 0 or fd >= MAX_FDS) {
            return -9; // EBADF
        }

        // Don't allow closing standard descriptors
        if (fd <= 2) {
            return -16; // EBUSY
        }

        closeFd(fd);
        return 0;
    }
};

// Inode management API
pub const allocInode = inode.alloc;
pub const freeInode = inode.free;

// Integrated file creation
pub fn createFile(file_type: types.FileType, inode_ops: *const InodeOperations, file_ops: *const FileOperations) ?*File {
    _ = file_ops; // TODO: Use this parameter
    const new_inode = allocInode(file_type, inode_ops) orelse return null;
    _ = new_inode; // TODO: Use this to create actual file
    // This would need integration with FileTable for actual file creation
    return null; // Placeholder - would return allocated File
}
