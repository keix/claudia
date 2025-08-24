// kernel/user/copy.zig - User space memory copy utilities
// Handles copying data between user and kernel space
// Uses proper MMU translation for safe user memory access

const std = @import("std");
const csr = @import("../arch/riscv/csr.zig");
const types = @import("../memory/types.zig");
const virtual = @import("../memory/virtual.zig");

// Helper function to translate user virtual address to physical address
fn translateUserAddress(user_va: usize) !usize {
    // Get current SATP value to determine which page table is active
    const satp = csr.readSatp();
    const ppn = satp & 0xFFFFFFFFFFF; // Extract PPN from SATP

    // For Sv39, we need to walk the 3-level page table
    const page_table_pa = ppn * types.PAGE_SIZE;

    // Extract VPN (Virtual Page Number) components
    const vpn2 = (user_va >> 30) & 0x1FF; // bits 38-30
    const vpn1 = (user_va >> 21) & 0x1FF; // bits 29-21
    const vpn0 = (user_va >> 12) & 0x1FF; // bits 20-12
    const offset = user_va & 0xFFF; // bits 11-0

    // Walk level 2 page table
    const l2_pte_addr = page_table_pa + vpn2 * 8;
    const l2_pte = @as(*const u64, @ptrFromInt(l2_pte_addr)).*;

    if ((l2_pte & 0x1) == 0) return error.PageNotPresent; // Valid bit
    if ((l2_pte & 0x6) != 0) return error.InvalidMapping; // Should not be leaf at L2

    // Walk level 1 page table
    const l2_ppn = (l2_pte >> 10) & 0xFFFFFFFFFFF;
    const l1_table_pa = l2_ppn * types.PAGE_SIZE;
    const l1_pte_addr = l1_table_pa + vpn1 * 8;
    const l1_pte = @as(*const u64, @ptrFromInt(l1_pte_addr)).*;

    if ((l1_pte & 0x1) == 0) return error.PageNotPresent;
    if ((l1_pte & 0x6) != 0) return error.InvalidMapping; // Should not be leaf at L1

    // Walk level 0 page table
    const l1_ppn = (l1_pte >> 10) & 0xFFFFFFFFFFF;
    const l0_table_pa = l1_ppn * types.PAGE_SIZE;
    const l0_pte_addr = l0_table_pa + vpn0 * 8;
    const l0_pte = @as(*const u64, @ptrFromInt(l0_pte_addr)).*;

    if ((l0_pte & 0x1) == 0) return error.PageNotPresent;
    if ((l0_pte & 0x6) == 0) return error.InvalidMapping; // Should be leaf at L0

    // Check if page is readable for user
    const user_bit = (l0_pte >> 4) & 0x1;
    const read_bit = (l0_pte >> 1) & 0x1;
    if (user_bit == 0 or read_bit == 0) return error.AccessDenied;

    // Extract physical page number and construct physical address
    const l0_ppn = (l0_pte >> 10) & 0xFFFFFFFFFFF;
    const phys_addr = l0_ppn * types.PAGE_SIZE + offset;

    return phys_addr;
}

/// Copy data from user space to kernel space
/// dst: kernel buffer to copy into
/// user_src: user space address to copy from
/// Returns: number of bytes copied on success
pub fn copyin(dst: []u8, user_src: usize) !usize {
    // Basic validation
    if (user_src < 0x10000) {
        return error.InvalidAddress;
    }

    // Check if this is a user space address (support legacy, ELF, and stack ranges)
    if ((user_src >= 0x40000000 and user_src < 0x50000000) or
        (user_src >= 0x01000000 and user_src < 0x02000000) or
        (user_src >= 0x50000000 and user_src < 0x60000000))
    { // User stack region
        // Use proper MMU translation for user addresses
        return copyinProper(dst, user_src);
    }

    // For kernel addresses, use direct access
    const p = @as([*]const u8, @ptrFromInt(user_src));
    @memcpy(dst, p[0..dst.len]);
    return dst.len;
}

/// Proper implementation using MMU translation
fn copyinProper(dst: []u8, user_src: usize) !usize {
    var bytes_copied: usize = 0;
    var src_addr = user_src;

    while (bytes_copied < dst.len) {
        // Translate virtual address to physical address
        const phys_addr = translateUserAddress(src_addr) catch |err| {
            return err;
        };

        // Calculate how many bytes we can copy from this page
        const page_offset = src_addr & (types.PAGE_SIZE - 1);
        const bytes_in_page = types.PAGE_SIZE - page_offset;
        const bytes_remaining = dst.len - bytes_copied;
        const bytes_to_copy = if (bytes_remaining > bytes_in_page) bytes_in_page else bytes_remaining;

        // Copy data from physical address
        const src_ptr = @as([*]const u8, @ptrFromInt(phys_addr));
        @memcpy(dst[bytes_copied .. bytes_copied + bytes_to_copy], src_ptr[0..bytes_to_copy]);

        bytes_copied += bytes_to_copy;
        src_addr += bytes_to_copy;
    }

    return bytes_copied;
}

/// Copy data from kernel space to user space
/// user_dst: user space address to copy to
/// src: kernel buffer to copy from
/// Returns: number of bytes copied on success
pub fn copyout(user_dst: usize, src: []const u8) !usize {
    // Basic validation
    if (user_dst < 0x10000) {
        return error.InvalidAddress;
    }

    // Check if this is a user space address (support legacy, ELF, and stack ranges)
    if ((user_dst >= 0x40000000 and user_dst < 0x50000000) or
        (user_dst >= 0x01000000 and user_dst < 0x02000000) or
        (user_dst >= 0x50000000 and user_dst < 0x60000000))
    { // User stack region
        // Use proper MMU translation for user addresses
        return copyoutProper(user_dst, src);
    }

    // For kernel addresses, use direct access
    const p = @as([*]u8, @ptrFromInt(user_dst));
    @memcpy(p[0..src.len], src);
    return src.len;
}

/// Proper implementation using MMU translation
fn copyoutProper(user_dst: usize, src: []const u8) !usize {
    var bytes_copied: usize = 0;
    var dst_addr = user_dst;

    while (bytes_copied < src.len) {
        // Translate virtual address to physical address
        const phys_addr = translateUserAddress(dst_addr) catch |err| {
            return err;
        };

        // Calculate how many bytes we can copy to this page
        const page_offset = dst_addr & (types.PAGE_SIZE - 1);
        const bytes_in_page = types.PAGE_SIZE - page_offset;
        const bytes_remaining = src.len - bytes_copied;
        const bytes_to_copy = if (bytes_remaining > bytes_in_page) bytes_in_page else bytes_remaining;

        // Copy data to physical address
        const dst_ptr = @as([*]u8, @ptrFromInt(phys_addr));
        @memcpy(dst_ptr[0..bytes_to_copy], src[bytes_copied .. bytes_copied + bytes_to_copy]);

        bytes_copied += bytes_to_copy;
        dst_addr += bytes_to_copy;
    }

    return bytes_copied;
}
