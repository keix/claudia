// Initrd loading and mounting support
const std = @import("std");
const simplefs = @import("../fs/simplefs.zig");
const ramdisk = @import("../driver/ramdisk.zig");
const uart = @import("../driver/uart/core.zig");
const dtb = @import("dtb.zig");
const memory = @import("../memory/types.zig");
const vfs = @import("../fs/vfs.zig");

// Boot parameters from assembly
extern var boot_hartid: usize;
extern var boot_dtb_ptr: usize;

// External symbols from linker script
extern const _end: u8;

// External symbols for embedded initrd
extern const _initrd_start: u8;
extern const _initrd_end: u8;

// Get initrd address 
pub fn getInitrdAddress() ?usize {
    // For QEMU virt machine, when using -kernel and -initrd:
    // - Kernel is loaded at 0x80200000
    // - Initrd is typically loaded at 0x88000000 (INITRD_PADDR in QEMU source)
    const QEMU_VIRT_INITRD: usize = 0x88000000;
    
    uart.puts("Checking for initrd at 0x");
    uart.putHex(QEMU_VIRT_INITRD);
    uart.puts("...\n");
    
    // Now check for SimpleFS magic
    const magic_ptr = @as(*const u32, @ptrFromInt(QEMU_VIRT_INITRD));
    const magic = magic_ptr.*;
    
    uart.puts("Magic read: 0x");
    uart.putHex(magic);
    uart.puts("\n");
    
    if (magic == 0x53494D50) { // 'SIMP'
        return QEMU_VIRT_INITRD;
    }
    
    uart.puts("Initrd not found at expected location\n");
    return null;
}

// Load initrd into a new ramdisk
pub fn loadInitrd() !void {
    
    // First, check for embedded initrd
    const embedded_start = @intFromPtr(&_initrd_start);
    const embedded_end = @intFromPtr(&_initrd_end);
    const embedded_size = embedded_end - embedded_start;
    
    if (embedded_size > 0) {
        
        // Check if it's a SimpleFS initrd
        const magic_ptr = @as(*const u32, @ptrFromInt(embedded_start));
        const magic = magic_ptr.*;
        
        if (magic == 0x53494D50) { // 'SIMP'
            // Load the embedded initrd
            const super_ptr = @as(*const simplefs.SuperBlock, @ptrFromInt(embedded_start));
            const total_blocks = super_ptr.total_blocks;
            const total_size = total_blocks * 512; // BLOCK_SIZE
            
            
            // Get the global ramdisk
            const ram_disk = ramdisk.getGlobalRamDisk() orelse {
                return;
            };
            
            // Copy initrd to ramdisk
            const initrd_data = @as([*]const u8, @ptrFromInt(embedded_start))[0..total_size];
            const ramdisk_data = ram_disk.getDataPtr();
            @memcpy(ramdisk_data[0..total_size], initrd_data);
            
            
            // Mount the filesystem
            const fs = simplefs.SimpleFS.mount(&ram_disk.device) catch |err| {
                uart.puts("Failed to mount initrd: ");
                if (err == error.InvalidFilesystem) {
                    uart.puts("Invalid filesystem\n");
                }
                return;
            };
            
            uart.puts("Initrd mounted successfully\n");
            
            // Populate VFS from SimpleFS
            populateVFS(fs);
            
            return;
        }
    }
    
    
    // No embedded initrd found
}

// Populate VFS from SimpleFS
fn populateVFS(fs: *simplefs.SimpleFS) void {
    
    uart.puts("Populating VFS from initrd:\n");
    
    // Iterate through all entries in SimpleFS
    for (&fs.files) |*entry| {
        if (entry.flags & simplefs.FLAG_EXISTS != 0) {
            const name = std.mem.sliceTo(&entry.name, 0);
            
            // Parse path components
            var path_parts: [10][]const u8 = undefined;
            var part_count: usize = 0;
            var start: usize = 0;
            
            // Split path by '/'
            for (name, 0..) |c, i| {
                if (c == '/') {
                    if (i > start) {
                        path_parts[part_count] = name[start..i];
                        part_count += 1;
                    }
                    start = i + 1;
                }
            }
            if (start < name.len) {
                path_parts[part_count] = name[start..];
                part_count += 1;
            }
            
            // Create directories and files in VFS
            if (entry.flags & simplefs.FLAG_DIRECTORY != 0) {
                // It's a directory
                uart.puts("  Creating directory: ");
                uart.puts(name);
                uart.puts("\n");
                
                _ = createVFSPath(path_parts[0..part_count], true);
            } else {
                // It's a file
                uart.puts("  Creating file: ");
                uart.puts(name);
                uart.puts(" (");
                uart.putDec(entry.size);
                uart.puts(" bytes)\n");
                
                // Create parent directories if needed
                if (part_count > 1) {
                    _ = createVFSPath(path_parts[0..part_count-1], true);
                }
                
                // Create the file
                if (createVFSPath(path_parts[0..part_count], false)) |file_node| {
                    // Load file content from SimpleFS
                    if (entry.size > 0 and entry.size <= file_node.data.len) {
                        var buffer: [1024]u8 = undefined;
                        const read_size = fs.readFile(name, &buffer) catch 0;
                        if (read_size > 0) {
                            @memcpy(file_node.data[0..read_size], buffer[0..read_size]);
                            file_node.data_size = read_size;
                        }
                    }
                }
            }
        }
    }
}

// Helper function to create a path in VFS
fn createVFSPath(path_parts: [][]const u8, is_directory: bool) ?*vfs.VNode {
    
    // Start from root
    var current_path: [256]u8 = undefined;
    var path_len: usize = 0;
    
    for (path_parts, 0..) |part, i| {
        // Build current path
        if (path_len > 0) {
            current_path[path_len] = '/';
            path_len += 1;
        }
        @memcpy(current_path[path_len..path_len + part.len], part);
        path_len += part.len;
        
        const current_path_str = current_path[0..path_len];
        
        // Check if this component exists
        if (vfs.resolvePath(current_path_str) == null) {
            // Create it
            const parent_path = if (i == 0) "/" else current_path[0..path_len - part.len - 1];
            
            if (i == path_parts.len - 1 and !is_directory) {
                // Last component and it's a file
                return vfs.createFile(parent_path, part);
            } else {
                // It's a directory or intermediate path component
                _ = vfs.createDirectory(parent_path, part);
            }
        }
    }
    
    return null;
}