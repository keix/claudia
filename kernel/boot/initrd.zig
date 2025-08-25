// Initrd loading and mounting support
const std = @import("std");
const simplefs = @import("../fs/simplefs.zig");
const ramdisk = @import("../driver/ramdisk.zig");
const uart = @import("../driver/uart/core.zig");
const dtb = @import("dtb.zig");
const memory = @import("../memory/types.zig");

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
            _ = simplefs.SimpleFS.mount(&ram_disk.device) catch |err| {
                uart.puts("Failed to mount initrd: ");
                if (err == error.InvalidFilesystem) {
                }
                return;
            };
            
            return;
        }
    }
    
    
    // No embedded initrd found
}