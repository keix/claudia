const std = @import("std");
const memory = @import("memory.zig");
const csr = @import("../arch/riscv/csr.zig");
const virtual = @import("../memory/virtual.zig");
const types = @import("../memory/types.zig");
const elf = @import("elf.zig");
const uart = @import("../driver/uart/core.zig");
const proc = @import("../process/core.zig");

extern fn switch_to_user_mode(entry_point: u64, user_stack: u64, kernel_stack: u64, satp_val: u64) void;

var test_user_context: memory.UserMemoryContext = undefined;

pub fn init() void {
    memory.init();
    test_user_context = memory.UserMemoryContext.init();
}

pub fn executeUserProgram(code: []const u8, args: []const u8) !noreturn {
    _ = args;

    const header = try elf.parseElfHeader(code);

    var new_user_context = memory.UserMemoryContext.init();
    try new_user_context.setupAddressSpace();

    const segments = elf.getLoadableSegments(code, header) orelse return error.NoLoadableSegments;

    try loadElfSegments(&new_user_context, code, segments);

    const user_ppn = new_user_context.getPageTablePPN() orelse return error.PageTableSetupFailed;

    try memory.mapElfSegments(&new_user_context);

    if (!memory.allocateRegion(&new_user_context.stack_region)) return error.StackAllocationFailed;
    try new_user_context.mapRegion(&new_user_context.stack_region);

    if (!new_user_context.verifyMapping(0x8021b000)) return error.KernelMappingFailed;
    if (!new_user_context.verifyMapping(memory.KERNEL_STACK_BASE + 0x1000)) return error.KernelStackMappingFailed;

    const asid: u16 = 0;
    const satp_value = composeSatp(user_ppn, asid);

    const user_stack = memory.USER_STACK_BASE + memory.USER_STACK_SIZE - 16;

    const kernel_sp = memory.getKernelStackTop();
    if (!new_user_context.verifyMapping(kernel_sp)) return error.KernelStackMappingFailed;

    test_user_context = new_user_context;
    csr.sfence_vma();

    if (!new_user_context.verifyMapping(0x8021b000)) return error.KernelMappingFailed;

    if (proc.Scheduler.getCurrentProcess()) |current| {
        const old_satp = current.context.satp;
        current.context.satp = satp_value;

        if (current.page_table_ppn != 0) {
            var old_pt = virtual.PageTable{ .root_ppn = current.page_table_ppn };
            old_pt.deinit();
        }

        current.page_table_ppn = user_ppn;
        current.heap_start = memory.USER_HEAP_BASE;
        current.heap_end = memory.USER_HEAP_BASE;

        if (csr.readSatp() == old_satp) {
            csr.writeSatp(satp_value);
            csr.sfence_vma();
        }
    }

    switch_to_user_mode(header.e_entry, user_stack, kernel_sp, satp_value);
    unreachable;
}

fn loadElfSegments(context: *memory.UserMemoryContext, code: []const u8, segments: []const elf.Elf64ProgramHeader) !void {
    for (segments) |segment| {
        if (segment.p_type != elf.PT_LOAD) continue;

        var perms: u8 = virtual.PTE_U | virtual.PTE_R;
        if (segment.p_flags & 0x2 != 0) perms |= virtual.PTE_W;
        if (segment.p_flags & 0x1 != 0) perms |= virtual.PTE_X;

        const aligned_vaddr = segment.p_vaddr & ~(types.PAGE_SIZE - 1);
        const aligned_end = (segment.p_vaddr + segment.p_memsz + types.PAGE_SIZE - 1) & ~(types.PAGE_SIZE - 1);

        const region = try memory.addElfSegment(context, aligned_vaddr, aligned_end - aligned_vaddr, perms);
        region.virtual_base = aligned_vaddr;

        if (!memory.allocateRegion(region)) return error.RegionAllocationFailed;

        if (segment.p_filesz > 0) {
            const data = code[segment.p_offset .. segment.p_offset + segment.p_filesz];
            const offset = segment.p_vaddr - aligned_vaddr;
            if (!memory.copyToRegion(region, offset, data)) return error.DataCopyFailed;
        }

        const bss_size = segment.p_memsz - segment.p_filesz;
        if (bss_size > 0) {
            const offset = (segment.p_vaddr - aligned_vaddr) + segment.p_filesz;
            if (!memory.zeroRegion(region, offset, bss_size)) return error.BssZeroFailed;
        }
    }
}

fn composeSatp(ppn: u64, asid: u16) u64 {
    const MODE_SV39: u64 = 8;
    return (MODE_SV39 << 60) | (@as(u64, asid) << 44) | ppn;
}

pub fn initActualUserMode() void {
    const _user_init_start = @extern([*]const u8, .{ .name = "_user_init_start" });
    const _user_init_end = @extern([*]const u8, .{ .name = "_user_init_end" });

    const start_addr = @intFromPtr(_user_init_start);
    const end_addr = @intFromPtr(_user_init_end);
    const code_size = end_addr - start_addr;

    if (code_size > 0 and code_size < 2097152) {
        const code = @as([*]const u8, @ptrFromInt(start_addr))[0..code_size];
        executeUserProgram(code, "") catch {
            while (true) csr.wfi();
        };
        unreachable;
    } else {
        while (true) csr.wfi();
    }
}
