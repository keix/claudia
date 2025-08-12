// User program management for Claudia kernel
// This will contain the real implementation for user program loading and execution

const std = @import("std");
const uart = @import("../driver/uart/core.zig");
const memory = @import("memory.zig");
const csr = @import("../arch/riscv/csr.zig");
const virtual = @import("../memory/virtual.zig");
const types = @import("../memory/types.zig");
const elf = @import("elf.zig");

// Import safe user mode switch function (includes SATP switching)
extern fn switch_to_user_mode(entry_point: u64, user_stack: u64, kernel_stack: u64, satp_val: u64) void;

// Global user memory context for testing
var test_user_context: memory.UserMemoryContext = undefined;

// Initialize user subsystem
pub fn init() void {
    memory.init();
    test_user_context = memory.UserMemoryContext.init();
    // User subsystem initialized
}

// Execute user ELF program with proper memory management
pub fn executeUserProgram(code: []const u8, args: []const u8) !void {
    _ = args;
    // Setting up user address space

    // Parse ELF header
    const header = elf.parseElfHeader(code) catch return;

    // Setup user address space
    test_user_context.setupAddressSpace() catch return;

    // User address space created successfully

    // Get loadable segments
    const segments = elf.getLoadableSegments(code, header) orelse {
        // No loadable segments found
        return;
    };

    // Create ELF segments in user memory context with page alignment
    for (segments) |segment| {
        if (segment.p_type != elf.PT_LOAD) continue;

        // Determine permissions based on segment flags
        var permissions: u8 = @as(u8, virtual.PTE_U); // Always user-accessible
        if (segment.p_flags & 0x4 != 0) permissions |= @as(u8, virtual.PTE_R); // Readable
        if (segment.p_flags & 0x2 != 0) permissions |= @as(u8, virtual.PTE_W); // Writable
        if (segment.p_flags & 0x1 != 0) permissions |= @as(u8, virtual.PTE_X); // Executable

        // Align segment to page boundaries
        const page_size: u64 = types.PAGE_SIZE;
        const aligned_vaddr = segment.p_vaddr & ~(page_size - 1); // Round down to page boundary
        const segment_end = segment.p_vaddr + segment.p_memsz;
        const aligned_end = (segment_end + page_size - 1) & ~(page_size - 1); // Round up to page boundary
        const aligned_size = aligned_end - aligned_vaddr;

        // Adding ELF segment

        const region = memory.addElfSegment(&test_user_context, aligned_vaddr, aligned_size, permissions) catch return;

        // Store original segment info for data copying
        region.virtual_base = aligned_vaddr;

        // Allocate physical memory for the segment
        if (!memory.allocateRegion(region)) {
            // Failed to allocate memory for ELF segment
            return;
        }

        // Copy segment data from ELF file with proper offset
        if (segment.p_filesz > 0) {
            const segment_data = code[segment.p_offset .. segment.p_offset + segment.p_filesz];
            const offset_in_region = segment.p_vaddr - aligned_vaddr;
            if (!memory.copyToRegion(region, offset_in_region, segment_data)) {
                // Failed to copy segment data
                return;
            }

            // Copied segment data
        }
    }

    // ELF segments prepared successfully

    // Get user page table PPN for SATP
    const user_ppn = test_user_context.getPageTablePPN() orelse {
        // Failed to get user page table PPN
        return;
    };

    // Switching to user address space

    // Map ELF segments to user page table
    memory.mapElfSegments(&test_user_context) catch return;

    // Allocate and map user stack
    if (!memory.allocateRegion(&test_user_context.stack_region)) {
        // Failed to allocate user stack
        return;
    }

    test_user_context.mapRegion(&test_user_context.stack_region) catch return;

    // User page table is now complete with kernel global mappings, ELF segments, and stack

    const asid: u16 = 0; // Use ASID 0 for simplicity first
    const satp_value = composeSatp(user_ppn, asid);

    // Set up user stack address
    const user_stack = memory.USER_STACK_BASE + memory.USER_STACK_SIZE - 16;

    // Get proper kernel stack from high common region
    const kernel_sp = memory.getKernelStackTop();

    // Switching to user mode

    // Verify kernel stack is properly mapped in user PT
    if (!test_user_context.verifyMapping(kernel_sp)) {
        // ERROR: Kernel stack not mapped in user PT!
        return;
    }
    // Kernel stack mapping verified

    // CRITICAL: After this call, we switch page tables inside the trampoline
    // No more UART access until we return via trap or the program exits
    switch_to_user_mode(header.e_entry, user_stack, kernel_sp, satp_value);

    // Should never reach here normally (user program exits via system call)
    // ERROR: Unexpectedly returned from user mode
}

// Compose SATP value with proper SV39 mode and ASID
fn composeSatp(ppn: u64, asid: u16) u64 {
    const MODE_SV39: u64 = 8;
    return (MODE_SV39 << 60) | (@as(u64, asid) << 44) | ppn;
}

pub fn initActualUserMode() void {
    // Executing /init

    // Get the init program code
    const _user_shell_start = @extern([*]const u8, .{ .name = "_user_shell_start" });
    const _user_shell_end = @extern([*]const u8, .{ .name = "_user_shell_end" });

    const start_addr = @intFromPtr(_user_shell_start);
    const end_addr = @intFromPtr(_user_shell_end);
    const code_size = end_addr - start_addr;

    // Check init binary size

    if (code_size > 0 and code_size < 2097152) { // Allow up to 2MB for shell
        const code = @as([*]const u8, @ptrFromInt(start_addr))[0..code_size];
        executeUserProgram(code, "") catch {};
    } else {
        // Invalid /init program size
    }
}
