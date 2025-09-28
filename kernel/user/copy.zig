const std = @import("std");
const csr = @import("../arch/riscv/csr.zig");
const types = @import("../memory/types.zig");
const virtual = @import("../memory/virtual.zig");

fn translateUserAddress(user_va: usize) !usize {
    const satp = csr.readSatp();
    const ppn = satp & 0xFFFFFFFFFFF;

    var pt = virtual.PageTable{ .root_ppn = ppn };
    const phys_addr = pt.translate(@intCast(user_va)) orelse return error.PageNotPresent;

    const vpn = [3]usize{
        (user_va >> 12) & 0x1FF, // VPN[0]
        (user_va >> 21) & 0x1FF, // VPN[1]
        (user_va >> 30) & 0x1FF, // VPN[2]
    };

    var table_pa = ppn * types.PAGE_SIZE;
    var level: usize = 2;
    while (level > 0) : (level -= 1) {
        const pte_addr = table_pa + vpn[level] * 8;
        const pte = @as(*const u64, @ptrFromInt(pte_addr)).*;
        if ((pte & 0x1) == 0) return error.PageNotPresent;
        table_pa = ((pte >> 10) & 0xFFFFFFFFFFF) * types.PAGE_SIZE;
    }

    const final_pte_addr = table_pa + vpn[0] * 8;
    const final_pte = @as(*const u64, @ptrFromInt(final_pte_addr)).*;

    if ((final_pte & virtual.PTE_U) == 0 or (final_pte & virtual.PTE_R) == 0) {
        return error.AccessDenied;
    }

    return phys_addr;
}

fn isUserAddress(addr: usize) bool {
    return (addr >= 0x01000000 and addr < 0x02000000) or
        (addr >= 0x40000000 and addr < 0x50000000) or
        (addr >= 0x50000000 and addr < 0x60000000);
}

fn copyMemory(dst_addr: usize, src_addr: usize, len: usize, to_user: bool) !usize {
    if ((to_user and dst_addr < 0x10000) or (!to_user and src_addr < 0x10000)) {
        return error.InvalidAddress;
    }

    const needs_translation = if (to_user) isUserAddress(dst_addr) else isUserAddress(src_addr);

    if (!needs_translation) {
        const src = @as([*]const u8, @ptrFromInt(src_addr))[0..len];
        const dst = @as([*]u8, @ptrFromInt(dst_addr))[0..len];
        @memcpy(dst, src);
        return len;
    }

    var bytes_copied: usize = 0;
    const user_addr = if (to_user) dst_addr else src_addr;
    var kernel_offset: usize = 0;

    while (bytes_copied < len) {
        const phys_addr = try translateUserAddress(user_addr + bytes_copied);

        const page_offset = (user_addr + bytes_copied) & (types.PAGE_SIZE - 1);
        const bytes_to_copy = @min(types.PAGE_SIZE - page_offset, len - bytes_copied);

        if (to_user) {
            const src = @as([*]const u8, @ptrFromInt(src_addr + kernel_offset))[0..bytes_to_copy];
            const dst = @as([*]u8, @ptrFromInt(phys_addr))[0..bytes_to_copy];
            @memcpy(dst, src);
        } else {
            const src = @as([*]const u8, @ptrFromInt(phys_addr))[0..bytes_to_copy];
            const dst = @as([*]u8, @ptrFromInt(dst_addr + kernel_offset))[0..bytes_to_copy];
            @memcpy(dst, src);
        }

        bytes_copied += bytes_to_copy;
        kernel_offset += bytes_to_copy;
    }

    return bytes_copied;
}

pub fn copyin(dst: []u8, user_src: usize) !usize {
    return copyMemory(@intFromPtr(dst.ptr), user_src, dst.len, false);
}

pub fn copyout(user_dst: usize, src: []const u8) !usize {
    return copyMemory(user_dst, @intFromPtr(src.ptr), src.len, true);
}

pub fn copyinstr(dst: []u8, user_src: usize) !usize {
    var i: usize = 0;
    while (i < dst.len - 1) : (i += 1) {
        var ch: [1]u8 = undefined;
        _ = try copyin(&ch, user_src + i);

        dst[i] = ch[0];
        if (ch[0] == 0) return i;
    }

    dst[i] = 0;
    return error.StringTooLong;
}
