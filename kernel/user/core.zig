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
    uart.puts("[user] User subsystem initialized\n");
}

// Execute user ELF program with proper memory management
pub fn executeUserProgram(code: []const u8, args: []const u8) !void {
    _ = args;
    uart.puts("[user] Setting up user address space\n");

    // Parse ELF header
    const header = elf.parseElfHeader(code) catch |err| {
        uart.puts("[user] ELF parsing failed: ");
        switch (err) {
            elf.ElfError.InvalidMagic => uart.puts("Invalid magic"),
            elf.ElfError.UnsupportedClass => uart.puts("Unsupported class"),
            elf.ElfError.UnsupportedMachine => uart.puts("Unsupported machine"),
            else => uart.puts("Unknown error"),
        }
        uart.puts("\n");
        return;
    };

    // Setup user address space
    test_user_context.setupAddressSpace() catch |err| {
        uart.puts("[user] Failed to setup address space: ");
        switch (err) {
            error.OutOfMemory => uart.puts("OutOfMemory"),
            else => uart.puts("Unknown error"),
        }
        uart.puts("\n");
        return;
    };

    uart.puts("[user] User address space created successfully\n");

    // Get loadable segments
    const segments = elf.getLoadableSegments(code, header) orelse {
        uart.puts("[user] No loadable segments found\n");
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

        uart.puts("[user] Adding ELF segment at ");
        uart.putHex(segment.p_vaddr);
        uart.puts(" (aligned ");
        uart.putHex(aligned_vaddr);
        uart.puts(") size ");
        uart.putHex(segment.p_memsz);
        uart.puts(" (aligned ");
        uart.putHex(aligned_size);
        uart.puts(") flags ");
        uart.putHex(segment.p_flags);
        uart.puts("\n");

        const region = memory.addElfSegment(&test_user_context, aligned_vaddr, aligned_size, permissions) catch |err| {
            uart.puts("[user] Failed to add ELF segment: ");
            switch (err) {
                error.TooManySegments => uart.puts("Too many segments"),
            }
            uart.puts("\n");
            return;
        };

        // Store original segment info for data copying
        region.virtual_base = aligned_vaddr;

        // Allocate physical memory for the segment
        if (!memory.allocateRegion(region)) {
            uart.puts("[user] Failed to allocate memory for ELF segment\n");
            return;
        }

        // Copy segment data from ELF file with proper offset
        if (segment.p_filesz > 0) {
            const segment_data = code[segment.p_offset .. segment.p_offset + segment.p_filesz];
            const offset_in_region = segment.p_vaddr - aligned_vaddr;
            if (!memory.copyToRegion(region, offset_in_region, segment_data)) {
                uart.puts("[user] Failed to copy segment data\n");
                return;
            }

            uart.puts("[user] Copied ");
            uart.putHex(segment.p_filesz);
            uart.puts(" bytes at offset ");
            uart.putHex(offset_in_region);
            uart.puts("\n");
        }
    }

    uart.puts("[user] ELF segments prepared successfully\n");

    // Get user page table PPN for SATP
    const user_ppn = test_user_context.getPageTablePPN() orelse {
        uart.puts("[user] Failed to get user page table PPN\n");
        return;
    };

    uart.puts("[user] Switching to user address space\n");
    uart.puts("[user] User PPN: ");
    uart.putHex(user_ppn);
    uart.puts("\n");

    // Map ELF segments to user page table
    memory.mapElfSegments(&test_user_context) catch |err| {
        uart.puts("[user] Failed to map ELF segments: ");
        switch (err) {
            error.NoPageTable => uart.puts("No page table"),
            error.OutOfMemory => uart.puts("Out of memory"),
            error.Misaligned => uart.puts("Misaligned"),
        }
        uart.puts("\n");
        return;
    };

    // Allocate and map user stack
    if (!memory.allocateRegion(&test_user_context.stack_region)) {
        uart.puts("[user] Failed to allocate user stack\n");
        return;
    }

    test_user_context.mapRegion(&test_user_context.stack_region) catch |err| {
        uart.puts("[user] Failed to map user stack: ");
        switch (err) {
            error.OutOfMemory => uart.puts("Out of memory"),
            error.Misaligned => uart.puts("Misaligned"),
        }
        uart.puts("\n");
        return;
    };

    // User page table is now complete with kernel global mappings, ELF segments, and stack
    uart.puts("[user] User page table ready, switching to U-mode\n");

    const asid: u16 = 0; // Use ASID 0 for simplicity first
    const satp_value = composeSatp(user_ppn, asid);

    // Set up user stack address
    const user_stack = memory.USER_STACK_BASE + memory.USER_STACK_SIZE - 16;

    // Get proper kernel stack from high common region
    const kernel_sp = memory.getKernelStackTop();

    uart.puts("[user] Entry: ");
    uart.putHex(header.e_entry);
    uart.puts(" User stack: ");
    uart.putHex(user_stack);
    uart.puts(" Kernel stack: ");
    uart.putHex(kernel_sp);
    uart.puts(" SATP: ");
    uart.putHex(satp_value);
    uart.puts("\n");

    // Verify kernel stack is properly mapped in user PT
    if (!test_user_context.verifyMapping(kernel_sp)) {
        uart.puts("[user] ERROR: Kernel stack not mapped in user PT!\n");
        return;
    }
    uart.puts("[user] Kernel stack mapping verified\n");

    // CRITICAL: After this call, we switch page tables inside the trampoline
    // No more UART access until we return via trap or the program exits
    switch_to_user_mode(header.e_entry, user_stack, kernel_sp, satp_value);

    // Should never reach here normally (user program exits via system call)
    uart.puts("[user] ERROR: Unexpectedly returned from user mode\n");
}

// Start shell - main user interface
pub fn runTests() void {
    // Start the shell as the main user program
    uart.puts("[user] Starting /init\n");
    testActualUserMode();
}

// Compose SATP value with proper SV39 mode and ASID
fn composeSatp(ppn: u64, asid: u16) u64 {
    const MODE_SV39: u64 = 8;
    return (MODE_SV39 << 60) | (@as(u64, asid) << 44) | ppn;
}

fn testActualUserMode() void {
    uart.puts("[user] Executing /init\n");

    // Get the init program code
    const _user_shell_start = @extern([*]const u8, .{ .name = "_user_shell_start" });
    const _user_shell_end = @extern([*]const u8, .{ .name = "_user_shell_end" });

    const start_addr = @intFromPtr(_user_shell_start);
    const end_addr = @intFromPtr(_user_shell_end);
    const code_size = end_addr - start_addr;

    uart.puts("[user] /init binary size: ");
    uart.putHex(code_size);
    uart.puts(" bytes\n");

    if (code_size > 0 and code_size < 2097152) { // Allow up to 2MB for shell
        const code = @as([*]const u8, @ptrFromInt(start_addr))[0..code_size];
        executeUserProgram(code, "") catch |err| {
            uart.puts("[user] Execute /init failed: ");
            switch (err) {
                else => uart.puts("Unknown error"),
            }
            uart.puts("\n");
        };
    } else {
        uart.puts("[user] Invalid /init program size: ");
        uart.putHex(code_size);
        uart.puts("\n");
    }
}
