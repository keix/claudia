// Device Tree Blob (DTB) parser
// Minimal implementation to extract initrd location
const std = @import("std");
const uart = @import("../driver/uart/core.zig");

// Boot parameters from assembly
extern var boot_dtb_ptr: usize;

// FDT header structure
const FdtHeader = extern struct {
    magic: u32,
    totalsize: u32,
    off_dt_struct: u32,
    off_dt_strings: u32,
    off_mem_rsvmap: u32,
    version: u32,
    last_comp_version: u32,
    boot_cpuid_phys: u32,
    size_dt_strings: u32,
    size_dt_struct: u32,
};

// FDT constants
const FDT_MAGIC: u32 = 0xd00dfeed;
const FDT_BEGIN_NODE: u32 = 0x00000001;
const FDT_END_NODE: u32 = 0x00000002;
const FDT_PROP: u32 = 0x00000003;
const FDT_NOP: u32 = 0x00000004;
const FDT_END: u32 = 0x00000009;

// Convert big-endian to little-endian
fn be32ToLe(val: u32) u32 {
    return ((val & 0xFF) << 24) |
           ((val & 0xFF00) << 8) |
           ((val & 0xFF0000) >> 8) |
           ((val & 0xFF000000) >> 24);
}

fn be64ToLe(val: u64) u64 {
    const high = be32ToLe(@intCast(val >> 32));
    const low = be32ToLe(@intCast(val & 0xFFFFFFFF));
    return (@as(u64, low) << 32) | high;
}

// Align to 4-byte boundary
fn align4(val: usize) usize {
    return (val + 3) & ~@as(usize, 3);
}

pub const InitrdInfo = struct {
    start: usize,
    end: usize,
};

// Parse DTB to find initrd location
pub fn findInitrd() ?InitrdInfo {
    const dtb_addr = boot_dtb_ptr;
    if (dtb_addr == 0) {
        uart.puts("No DTB provided\n");
        return null;
    }

    uart.puts("DTB at 0x");
    uart.putHex(dtb_addr);
    uart.puts("\n");

    // Validate DTB address is in mapped range
    if (dtb_addr < 0x80000000 or dtb_addr > 0xa0000000) {
        uart.puts("DTB address out of range\n");
        return null;
    }

    // Try to read first word to test access
    const test_ptr = @as(*const volatile u32, @ptrFromInt(dtb_addr));
    const first_word = test_ptr.*;
    
    uart.puts("First word at DTB: 0x");
    uart.putHex(first_word);
    uart.puts("\n");
    
    // Read FDT header
    const header = @as(*const FdtHeader, @ptrFromInt(dtb_addr));
    
    // Check magic number
    const magic = be32ToLe(header.magic);
    if (magic != FDT_MAGIC) {
        uart.puts("Invalid DTB magic: 0x");
        uart.putHex(magic);
        uart.puts("\n");
        return null;
    }

    // Get offsets
    const struct_offset = be32ToLe(header.off_dt_struct);
    const strings_offset = be32ToLe(header.off_dt_strings);
    
    // Start parsing structure
    var offset = dtb_addr + struct_offset;
    var depth: u32 = 0;
    var in_chosen = false;
    var initrd_start: ?usize = null;
    var initrd_end: ?usize = null;

    while (true) {
        const token_ptr = @as(*const u32, @ptrFromInt(offset));
        const token = be32ToLe(token_ptr.*);
        offset += 4;

        switch (token) {
            FDT_BEGIN_NODE => {
                // Node name follows
                const name_ptr = @as([*:0]const u8, @ptrFromInt(offset));
                const name = std.mem.sliceTo(name_ptr, 0);
                
                if (depth == 0 and std.mem.eql(u8, name, "chosen")) {
                    in_chosen = true;
                }
                
                depth += 1;
                offset = align4(offset + name.len + 1);
            },
            FDT_END_NODE => {
                depth -= 1;
                if (depth == 0) in_chosen = false;
            },
            FDT_PROP => {
                // Property header
                const len = be32ToLe(@as(*const u32, @ptrFromInt(offset)).*);
                const nameoff = be32ToLe(@as(*const u32, @ptrFromInt(offset + 4)).*);
                offset += 8;

                // Get property name
                const prop_name_ptr = @as([*:0]const u8, @ptrFromInt(dtb_addr + strings_offset + nameoff));
                const prop_name = std.mem.sliceTo(prop_name_ptr, 0);

                // Property data
                // const data_ptr = @as([*]const u8, @ptrFromInt(offset));

                if (in_chosen) {
                    if (std.mem.eql(u8, prop_name, "linux,initrd-start")) {
                        if (len == 4) {
                            initrd_start = be32ToLe(@as(*const u32, @ptrFromInt(offset)).*);
                        } else if (len == 8) {
                            initrd_start = be64ToLe(@as(*const u64, @ptrFromInt(offset)).*);
                        }
                    } else if (std.mem.eql(u8, prop_name, "linux,initrd-end")) {
                        if (len == 4) {
                            initrd_end = be32ToLe(@as(*const u32, @ptrFromInt(offset)).*);
                        } else if (len == 8) {
                            initrd_end = be64ToLe(@as(*const u64, @ptrFromInt(offset)).*);
                        }
                    }
                }

                offset = align4(offset + len);
            },
            FDT_NOP => {},
            FDT_END => break,
            else => {
                uart.puts("Unknown FDT token: 0x");
                uart.putHex(token);
                uart.puts("\n");
                return null;
            },
        }
    }

    if (initrd_start != null and initrd_end != null) {
        uart.puts("Found initrd in DTB: 0x");
        uart.putHex(initrd_start.?);
        uart.puts(" - 0x");
        uart.putHex(initrd_end.?);
        uart.puts("\n");
        
        return InitrdInfo{
            .start = initrd_start.?,
            .end = initrd_end.?,
        };
    }

    uart.puts("No initrd info found in DTB\n");
    return null;
}