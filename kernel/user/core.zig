// User program management for Claudia kernel
// This will contain the real implementation for user program loading and execution

const std = @import("std");
const memory = @import("memory.zig");
const csr = @import("../arch/riscv/csr.zig");
const virtual = @import("../memory/virtual.zig");
const types = @import("../memory/types.zig");
const elf = @import("elf.zig");
const uart = @import("../driver/uart/core.zig");

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

// Execute user ELF program with proper memory management - noreturn on success
pub fn executeUserProgram(code: []const u8, args: []const u8) !noreturn {
    _ = args;

    uart.puts("[executeUserProgram] Starting user program execution\n");
    uart.puts("  Code size: 0x");
    uart.putHex(code.len);
    uart.puts(" bytes\n");

    // Parse ELF header
    const header = elf.parseElfHeader(code) catch return error.InvalidELF;

    // For exec: Create a completely new memory context to replace the old one
    var new_user_context = memory.UserMemoryContext.init();

    // Setup new address space
    new_user_context.setupAddressSpace() catch |err| {
        uart.puts("[executeUserProgram] ERROR: setupAddressSpace failed: ");
        switch (err) {
            error.OutOfMemory => uart.puts("OutOfMemory"),
            else => uart.puts("Unknown error"),
        }
        uart.puts("\n");
        return error.MemorySetupFailed;
    };

    // User address space created successfully

    // Get loadable segments
    const segments = elf.getLoadableSegments(code, header) orelse {
        // No loadable segments found
        return error.NoLoadableSegments;
    };

    // Create ELF segments in user memory context with page alignment
    var segment_idx: u32 = 0;
    for (segments) |segment| {
        if (segment.p_type != elf.PT_LOAD) continue;

        // Determine permissions based on segment flags
        var permissions: u8 = @as(u8, virtual.PTE_U | virtual.PTE_R); // Always user-accessible and readable
        if (segment.p_flags & 0x2 != 0) permissions |= @as(u8, virtual.PTE_W); // Writable
        if (segment.p_flags & 0x1 != 0) permissions |= @as(u8, virtual.PTE_X); // Executable

        // Align segment to page boundaries
        const page_size: u64 = types.PAGE_SIZE;
        const aligned_vaddr = segment.p_vaddr & ~(page_size - 1); // Round down to page boundary
        const segment_end = segment.p_vaddr + segment.p_memsz;
        const aligned_end = (segment_end + page_size - 1) & ~(page_size - 1); // Round up to page boundary
        const aligned_size = aligned_end - aligned_vaddr;

        const region = memory.addElfSegment(&new_user_context, aligned_vaddr, aligned_size, permissions) catch return error.SegmentSetupFailed;

        // Store original segment info for data copying
        region.virtual_base = aligned_vaddr;

        // Allocate physical memory for the segment
        if (!memory.allocateRegion(region)) {
            // Failed to allocate memory for ELF segment
            return error.RegionAllocationFailed;
        }

        // Copy segment data from ELF file with proper offset
        if (segment.p_filesz > 0) {
            const segment_data = code[segment.p_offset .. segment.p_offset + segment.p_filesz];
            const offset_in_region = segment.p_vaddr - aligned_vaddr;
            if (!memory.copyToRegion(region, offset_in_region, segment_data)) {
                // Failed to copy segment data
                return error.DataCopyFailed;
            }
        }

        // Zero .bss area if memsz > filesz
        const bss_size = segment.p_memsz - segment.p_filesz;
        if (bss_size > 0) {
            // Zero .bss area - offset starts after copied file data
            const offset_in_region = (segment.p_vaddr - aligned_vaddr) + segment.p_filesz;
            if (!memory.zeroRegion(region, offset_in_region, bss_size)) {
                return error.BssZeroFailed;
            }
        }

        segment_idx += 1;
    }

    // ELF segments prepared successfully

    // Get user page table PPN for SATP
    const user_ppn = new_user_context.getPageTablePPN() orelse {
        // Failed to get user page table PPN
        return error.PageTableSetupFailed;
    };

    // Switching to user address space

    // Map ELF segments to user page table
    memory.mapElfSegments(&new_user_context) catch return error.MappingFailed;

    // Allocate and map user stack
    if (!memory.allocateRegion(&new_user_context.stack_region)) {
        // Failed to allocate user stack
        return error.StackAllocationFailed;
    }

    new_user_context.mapRegion(&new_user_context.stack_region) catch return error.StackMappingFailed;

    // User page table is now complete with kernel global mappings, ELF segments, and stack

    // Verify critical kernel mappings in user page table
    uart.puts("[executeUserProgram] Verifying kernel mappings in user PT...\n");

    // Check a kernel code address (current PC area)
    const test_kernel_addr: u64 = 0x8021b000; // Near the fault address
    if (new_user_context.verifyMapping(test_kernel_addr)) {
        uart.puts("  Kernel code (0x8021b000): MAPPED\n");
    } else {
        uart.puts("  ERROR: Kernel code (0x8021b000): NOT MAPPED!\n");
        return error.KernelMappingFailed;
    }

    // Check kernel stack
    const kernel_stack_test = memory.KERNEL_STACK_BASE + 0x1000;
    if (new_user_context.verifyMapping(kernel_stack_test)) {
        uart.puts("  Kernel stack: MAPPED\n");
    } else {
        uart.puts("  ERROR: Kernel stack: NOT MAPPED!\n");
        return error.KernelStackMappingFailed;
    }

    const asid: u16 = 0; // Use ASID 0 for simplicity first
    const satp_value = composeSatp(user_ppn, asid);

    uart.puts("[executeUserProgram] Page table info:\n");
    uart.puts("  User page table PPN: 0x");
    uart.putHex(user_ppn);
    uart.puts("\n  User PT pointer: 0x");
    uart.putHex(@intFromPtr(new_user_context.page_table));
    uart.puts("\n  User PT root_ppn in struct: 0x");
    if (new_user_context.page_table) |pt| {
        uart.putHex(pt.root_ppn);
    } else {
        uart.puts("NULL");
    }
    uart.puts("\n");

    // Set up user stack address
    const user_stack = memory.USER_STACK_BASE + memory.USER_STACK_SIZE - 16;

    // Get proper kernel stack from high common region
    const kernel_sp = memory.getKernelStackTop();

    // Switching to user mode

    // Verify kernel stack is properly mapped in user PT
    if (!new_user_context.verifyMapping(kernel_sp)) {
        // ERROR: Kernel stack not mapped in user PT!
        return error.KernelStackMappingFailed;
    }
    // Kernel stack mapping verified

    // Replace the global user context with the new one for exec
    // This ensures subsequent operations use the new address space
    test_user_context = new_user_context;

    // Ensure TLB is flushed after switching to user address space
    csr.sfence_vma();

    uart.puts("[executeUserProgram] About to switch to user mode\n");
    uart.puts("  Entry point: 0x");
    uart.putHex(header.e_entry);
    uart.puts("\n  User stack: 0x");
    uart.putHex(user_stack);
    uart.puts("\n  Kernel stack: 0x");
    uart.putHex(kernel_sp);
    uart.puts("\n  SATP value: 0x");
    uart.putHex(satp_value);
    uart.puts("\n");

    // Final check: is kernel code still mapped?
    const final_test_addr: u64 = 0x8021b000;
    if (new_user_context.verifyMapping(final_test_addr)) {
        uart.puts("  Final check: Kernel code at 0x8021b000 is MAPPED\n");

        // Extra paranoid check - manually walk the page table
        if (new_user_context.page_table) |pt| {
            const root_addr = pt.root_ppn << 12;
            const root_table = @as([*]const u64, @ptrFromInt(root_addr));
            const vpn2 = (0x8021b000 >> 30) & 0x1FF;
            const l2_pte = root_table[vpn2];

            uart.puts("  Manual check - L2 PTE[");
            uart.putHex(vpn2);
            uart.puts("] at root 0x");
            uart.putHex(root_addr);
            uart.puts(" = 0x");
            uart.putHex(l2_pte);
            uart.puts("\n");

            if (l2_pte == 0) {
                uart.puts("  CRITICAL ERROR: L2 PTE is zero! Page table corrupted!\n");
            }
        }
    } else {
        uart.puts("  ERROR: Kernel code at 0x8021b000 is NOT MAPPED!\n");
    }

    // Save critical PTE value for debugging
    const saved_l2_pte: u64 = if (new_user_context.page_table) |pt| blk: {
        const root_addr = pt.root_ppn << 12;
        const root_table = @as([*]const u64, @ptrFromInt(root_addr));
        const vpn2 = (0x8021b000 >> 30) & 0x1FF;
        break :blk root_table[vpn2];
    } else 0;

    uart.puts("  Saved L2 PTE before switch: 0x");
    uart.putHex(saved_l2_pte);
    uart.puts("\n");

    // CRITICAL FIX: Update current process's kernel context SATP
    // This ensures when we return from interrupts/syscalls, we use the new page table
    const proc = @import("../process/core.zig");
    if (proc.Scheduler.getCurrentProcess()) |current| {
        const old_satp = current.context.satp;
        uart.puts("  Updating process kernel context SATP from 0x");
        uart.putHex(old_satp);
        uart.puts(" to 0x");
        uart.putHex(satp_value);
        uart.puts("\n");

        // Extract old PPN to check if it's the problematic one
        const old_ppn = old_satp & 0xFFFFFFFFFFF;
        if (old_ppn == 0x802cf) {
            uart.puts("  WARNING: Process was using page table 0x802cf without kernel mappings!\n");
        }

        current.context.satp = satp_value;

        // Also update the current CPU's SATP immediately if we're running on this process
        const current_cpu_satp = csr.readSatp();
        if (current_cpu_satp == old_satp) {
            uart.puts("  Also updating current CPU SATP\n");
            csr.writeSatp(satp_value);
            csr.sfence_vma();
        }
    }

    uart.puts("  Switching to user mode NOW...\n");
    switch_to_user_mode(header.e_entry, user_stack, kernel_sp, satp_value);

    // Should never reach here normally (user program exits via system call)
    unreachable;
}

// Compose SATP value with proper SV39 mode and ASID
fn composeSatp(ppn: u64, asid: u16) u64 {
    const MODE_SV39: u64 = 8;
    return (MODE_SV39 << 60) | (@as(u64, asid) << 44) | ppn;
}

pub fn initActualUserMode() void {
    uart.puts("[initActualUserMode] Starting init process setup\n");

    // Executing /sbin/init

    // Get the init program code
    const _user_init_start = @extern([*]const u8, .{ .name = "_user_init_start" });
    const _user_init_end = @extern([*]const u8, .{ .name = "_user_init_end" });

    const start_addr = @intFromPtr(_user_init_start);
    const end_addr = @intFromPtr(_user_init_end);
    const code_size = end_addr - start_addr;

    // Check init binary size

    if (code_size > 0 and code_size < 2097152) { // Allow up to 2MB for init
        const code = @as([*]const u8, @ptrFromInt(start_addr))[0..code_size];

        uart.puts("[initActualUserMode] About to call executeUserProgram\n");
        uart.puts("  Code at: 0x");
        uart.putHex(start_addr);
        uart.puts(", size: 0x");
        uart.putHex(code_size);
        uart.puts("\n");

        executeUserProgram(code, "") catch {
            uart.puts("[initActualUserMode] executeUserProgram failed\n");
            // Failed to execute /sbin/init - this should not happen
            while (true) {
                csr.wfi();
            }
        };
        unreachable; // Should never reach here if executeUserProgram succeeds
    } else {
        // Invalid /sbin/init program size
        while (true) {
            csr.wfi();
        }
    }
}
