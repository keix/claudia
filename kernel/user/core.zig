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

// Execute user ELF program with proper memory management - noreturn on success
pub fn executeUserProgram(code: []const u8, args: []const u8) !noreturn {
    return executeUserProgramWithSeq(code, args, 0);
}

// Execute user ELF program with sequence number for debugging
pub fn executeUserProgramWithSeq(code: []const u8, args: []const u8, seq: u32) !noreturn {
    _ = args;
    uart.puts("[exec#");
    uart.putHex(seq);
    uart.puts("] Setting up NEW user address space\n");

    // Parse ELF header
    const header = elf.parseElfHeader(code) catch return error.InvalidELF;

    // For exec: Create a completely new memory context to replace the old one
    var new_user_context = memory.UserMemoryContext.init();
    
    // Setup new address space
    new_user_context.setupAddressSpace() catch return error.MemorySetupFailed;

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
        
        uart.puts("[exec#");
        uart.putHex(seq);
        uart.puts(" ph#");
        uart.putHex(segment_idx);
        uart.puts("] Processing PT_LOAD vaddr=0x");
        uart.putHex(segment.p_vaddr);
        uart.puts(" filesz=0x");
        uart.putHex(segment.p_filesz);
        uart.puts(" memsz=0x");
        uart.putHex(segment.p_memsz);
        uart.puts(" flags=0x");
        uart.putHex(segment.p_flags);
        uart.puts("\n");

        // Determine permissions based on segment flags
        var permissions: u8 = @as(u8, virtual.PTE_U | virtual.PTE_R); // Always user-accessible and readable
        if (segment.p_flags & 0x2 != 0) permissions |= @as(u8, virtual.PTE_W); // Writable
        if (segment.p_flags & 0x1 != 0) permissions |= @as(u8, virtual.PTE_X); // Executable
        
        uart.puts("[exec#");
        uart.putHex(seq);
        uart.puts(" ph#");
        uart.putHex(segment_idx);
        uart.puts("] Permissions: 0x");
        uart.putHex(permissions);
        uart.puts(" (");
        if (permissions & virtual.PTE_R != 0) uart.puts("R");
        if (permissions & virtual.PTE_W != 0) uart.puts("W");
        if (permissions & virtual.PTE_X != 0) uart.puts("X");
        if (permissions & virtual.PTE_U != 0) uart.puts("U");
        uart.puts(")\n");

        // Align segment to page boundaries
        const page_size: u64 = types.PAGE_SIZE;
        const aligned_vaddr = segment.p_vaddr & ~(page_size - 1); // Round down to page boundary
        const segment_end = segment.p_vaddr + segment.p_memsz;
        const aligned_end = (segment_end + page_size - 1) & ~(page_size - 1); // Round up to page boundary
        const aligned_size = aligned_end - aligned_vaddr;

        uart.puts("[exec#");
        uart.putHex(seq);
        uart.puts(" ph#");
        uart.putHex(segment_idx);
        uart.puts("] Aligned vaddr=0x");
        uart.putHex(aligned_vaddr);
        uart.puts(" size=0x");
        uart.putHex(aligned_size);
        uart.puts("\n");

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
            uart.puts("[exec#");
            uart.putHex(seq);
            uart.puts(" ph#");
            uart.putHex(segment_idx);
            uart.puts("] Copy filesz=0x");
            uart.putHex(segment.p_filesz);
            uart.puts("\n");
            
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
            uart.puts("[exec#");
            uart.putHex(seq);
            uart.puts(" ph#");
            uart.putHex(segment_idx);
            uart.puts("] .bss zero=0x");
            uart.putHex(bss_size);
            uart.puts("\n");
            
            // Zero .bss area - offset starts after copied file data
            const offset_in_region = (segment.p_vaddr - aligned_vaddr) + segment.p_filesz;
            if (!memory.zeroRegion(region, offset_in_region, bss_size)) {
                uart.puts("[exec#");
                uart.putHex(seq);
                uart.puts(" ph#");
                uart.putHex(segment_idx);
                uart.puts("] ERROR: Failed to zero .bss area\n");
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

    const asid: u16 = 0; // Use ASID 0 for simplicity first
    const satp_value = composeSatp(user_ppn, asid);

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

    // CRITICAL: After this call, we switch page tables inside the trampoline
    // No more UART access until we return via trap or the program exits
    uart.puts("[exec#");
    uart.putHex(seq);
    uart.puts("] Switching to user mode entry=0x");
    uart.putHex(header.e_entry);
    uart.puts(" satp=0x");
    uart.putHex(satp_value);
    uart.puts("\n");
    
    // Ensure TLB is flushed after switching to user address space
    csr.sfence_vma();
    
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
        executeUserProgram(code, "") catch {
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
