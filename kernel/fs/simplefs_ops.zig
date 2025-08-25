// SimpleFS operations exposed to userland
const std = @import("std");
const simplefs = @import("simplefs.zig");
const ramdisk = @import("../driver/ramdisk.zig");

// Use a pointer to SimpleFS
var fs: ?*simplefs.SimpleFS = null;
var mounted = false;

// State for file reading
var read_file_state: struct {
    active: bool = false,
    file_name: [32]u8 = undefined,
    file_name_len: usize = 0,
    file_size: usize = 0,
    read_pos: usize = 0,
} = .{};

pub fn mount() !void {
    if (mounted) {
        return;
    }
    
    const ram_disk = ramdisk.getGlobalRamDisk() orelse return error.NoRamDisk;
    const device_ptr = &ram_disk.device;
    
    fs = simplefs.SimpleFS.mount(device_ptr) catch |err| {
        return err;
    };
    
    mounted = true;
}

pub fn createFile(name: []const u8, content: []const u8) !void {
    if (!mounted) {
        try mount();
    }
    
    var fs_instance = fs orelse return error.NotMounted;
    try fs_instance.createFile(name, content);
}

pub fn readFile(name: []const u8, buffer: []u8) !usize {
    if (!mounted) try mount();
    
    var fs_instance = fs orelse return error.NotMounted;
    return try fs_instance.readFile(name, buffer);
}

pub fn listFiles() void {
    if (!mounted) {
        mount() catch {
            const uart = @import("../driver/uart/core.zig");
            uart.puts("Error: SimpleFS not mounted\n");
            return;
        };
    }
    
    if (fs) |fs_instance| {
        fs_instance.listFiles();
    }
}

fn setReadFileState(name: []const u8) !void {
    if (!mounted) try mount();
    
    var fs_instance = fs orelse return error.NotMounted;
    
    // Find file
    for (&fs_instance.files) |*entry| {
        if (entry.flags == 1) {
            const entry_name = std.mem.sliceTo(&entry.name, 0);
            if (std.mem.eql(u8, entry_name, name)) {
                // Set up read state
                read_file_state.active = true;
                @memcpy(read_file_state.file_name[0..name.len], name);
                read_file_state.file_name_len = name.len;
                read_file_state.file_size = entry.size;
                read_file_state.read_pos = 0;
                return;
            }
        }
    }
    
    return error.FileNotFound;
}

// Called when block device is read after a read file command
pub fn handleFileRead(buffer: []u8) !usize {
    if (!read_file_state.active) return error.NoActiveRead;
    
    defer {
        read_file_state.active = false;
        read_file_state.read_pos = 0;
    }
    
    const name = read_file_state.file_name[0..read_file_state.file_name_len];
    return try readFile(name, buffer);
}

// Handle commands from userland through a simple protocol
pub fn handleCommand(buffer: []const u8) !usize {
    if (buffer.len < 1) return error.InvalidCommand;
    
    const cmd = buffer[0];
    
    switch (cmd) {
        0x00 => { // Format
            // Get the RAM disk
            const ram_disk = ramdisk.getGlobalRamDisk() orelse return error.NoRamDisk;
            
            // Format the device
            try simplefs.SimpleFS.format(&ram_disk.device);
            
            // Reset mount state
            mounted = false;
            fs = null;
            
            return 0;
        },
        0x01 => { // Create file
            if (buffer.len < 7) return error.InvalidCommand;
            
            const name_len = buffer[1];
            if (buffer.len < 2 + name_len + 4) return error.InvalidCommand;
            
            const name = buffer[2..2 + name_len];
            
            const content_len_offset = 2 + name_len;
            const content_len_bytes = buffer[content_len_offset..content_len_offset + 4];
            const content_len = content_len_bytes[0] | 
                               (@as(u32, content_len_bytes[1]) << 8) |
                               (@as(u32, content_len_bytes[2]) << 16) |
                               (@as(u32, content_len_bytes[3]) << 24);
            
            const content_offset = content_len_offset + 4;
            if (buffer.len < content_offset + content_len) return error.InvalidCommand;
            
            const content = buffer[content_offset..content_offset + content_len];
            
            try createFile(name, content);
            
            return 0;
        },
        0x02 => { // Read file - returns file content through block device read
            if (buffer.len < 2) return error.InvalidCommand;
            
            const name_len = buffer[1];
            if (buffer.len < 2 + name_len) return error.InvalidCommand;
            
            const name = buffer[2..2 + name_len];
            
            // Set up state for subsequent read operation
            setReadFileState(name) catch return error.FileNotFound;
            
            // Return 0 to indicate command processed
            return 0;
        },
        0x03 => { // List files
            listFiles();
            return 0;
        },
        else => return error.UnknownCommand,
    }
}