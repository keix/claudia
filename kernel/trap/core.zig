// Trap handling for RISC-V
// Manages system calls and exceptions from user mode

const std = @import("std");
const csr = @import("../arch/riscv/csr.zig");
const uart = @import("../driver/uart/core.zig");
const proc = @import("../process/core.zig");
const file = @import("../file/core.zig");
const defs = @import("abi");
const sysno = @import("sysno");
const copy = @import("../user/copy.zig");
const dispatch = @import("../syscalls/dispatch.zig");
const memory = @import("../memory/core.zig");

// Import trap vector from assembly
extern const trap_vector: u8;

// Trap frame structure matching the assembly layout
pub const TrapFrame = struct {
    sepc: u64, // 0: Supervisor Exception Program Counter
    ra: u64, // 8: Return address (x1)
    gp: u64, // 16: Global pointer (x3)
    tp: u64, // 24: Thread pointer (x4)
    t0: u64, // 32: Temporary (x5)
    t1: u64, // 40: Temporary (x6)
    t2: u64, // 48: Temporary (x7)
    s0: u64, // 56: Saved register (x8)
    s1: u64, // 64: Saved register (x9)
    a0: u64, // 72: Function argument/return value (x10)
    a1: u64, // 80: Function argument (x11)
    a2: u64, // 88: Function argument (x12)
    a3: u64, // 96: Function argument (x13)
    a4: u64, // 104: Function argument (x14)
    a5: u64, // 112: Function argument (x15)
    a6: u64, // 120: Function argument (x16)
    a7: u64, // 128: Function argument/syscall number (x17)
    s2: u64, // 136: Saved register (x18)
    s3: u64, // 144: Saved register (x19)
    s4: u64, // 152: Saved register (x20)
    s5: u64, // 160: Saved register (x21)
    s6: u64, // 168: Saved register (x22)
    s7: u64, // 176: Saved register (x23)
    s8: u64, // 184: Saved register (x24)
    s9: u64, // 192: Saved register (x25)
    s10: u64, // 200: Saved register (x26)
    s11: u64, // 208: Saved register (x27)
    t3: u64, // 216: Temporary (x28)
    t4: u64, // 224: Temporary (x29)
    t5: u64, // 232: Temporary (x30)
    t6: u64, // 240: Temporary (x31)
    sp: u64, // 248: Stack pointer (x2)
    scause: u64, // 256: Supervisor Trap Cause
    stval: u64, // 264: Supervisor Trap Value
};

// Exception causes
const ExceptionCause = enum(u64) {
    InstructionAddressMisaligned = 0,
    InstructionAccessFault = 1,
    IllegalInstruction = 2,
    Breakpoint = 3,
    LoadAddressMisaligned = 4,
    LoadAccessFault = 5,
    StoreAddressMisaligned = 6,
    StoreAccessFault = 7,
    EcallFromUMode = 8,
    EcallFromSMode = 9,
    EcallFromMMode = 11,
    InstructionPageFault = 12,
    LoadPageFault = 13,
    StorePageFault = 15,
};

// Track TLB retry attempts to prevent infinite loops
var tlb_retry_count: u32 = 0;
var last_fault_addr: u64 = 0;

// Initialize trap handling
pub fn init() void {

    // Set trap vector
    const trap_vector_addr = @intFromPtr(&trap_vector);
    csr.writeStvec(trap_vector_addr);

    // Initialize syscall dispatcher with file system function pointers
    dispatch.init(
        fileGetFile,
        fileWrite,
        fileRead,
        fileClose,
        procExit,
        procFork,
        procExec,
    );
}

// File system function wrappers for dispatcher
fn fileGetFile(fd: i32) ?*anyopaque {
    return @as(?*anyopaque, @ptrCast(file.FileTable.getFile(fd)));
}

fn fileWrite(f: *anyopaque, data: []const u8) isize {
    const file_ptr = @as(*file.File, @ptrCast(@alignCast(f)));
    return file_ptr.write(data);
}

fn fileRead(f: *anyopaque, buffer: []u8) isize {
    const file_ptr = @as(*file.File, @ptrCast(@alignCast(f)));
    return file_ptr.read(buffer);
}

fn fileClose(fd: i32) isize {
    return file.FileTable.sysClose(fd);
}

fn procExit(code: i32) noreturn {
    proc.Scheduler.exit(code);
    // Should not reach here
    while (true) {
        csr.wfi();
    }
}

fn procFork() isize {
    return proc.Scheduler.fork();
}

fn procExec(filename: []const u8, args: []const u8) isize {
    return proc.Scheduler.exec(filename, args);
}

// Helper to check PTE corruption at any point
fn checkPTECorruption(label: []const u8) void {
    const current_satp = csr.readSatp();
    const current_ppn = current_satp & 0xFFFFFFFFFFF;
    if (current_ppn == 0x802bf or current_ppn == 0x802cf) {
        const root_addr = current_ppn << 12;
        const root_table = @as([*]const volatile u64, @ptrFromInt(root_addr));
        const vpn2 = (0x8021b000 >> 30) & 0x1FF; // VPN2 index for kernel code

        // Force memory barrier
        asm volatile ("fence rw, rw" ::: "memory");

        const l2_pte = root_table[vpn2];
        if (l2_pte == 0) {
            uart.puts("[PTE CORRUPTION] Detected at: ");
            uart.puts(label);
            uart.puts("\n");
            uart.puts("  Page table 0x");
            uart.putHex(current_ppn);
            uart.puts(": L2 PTE[0x");
            uart.putHex(vpn2);
            uart.puts("] is ZERO!\n");

            // Halt to prevent further damage
            while (true) {
                csr.wfi();
            }
        }
    }
}

// Main trap handler called from assembly
pub export fn trapHandler(frame: *TrapFrame) void {
    // First, save the original values before they might change
    const scause_val = frame.scause;
    const stval_val = frame.stval;
    const sepc_val = frame.sepc;

    // Debug: Log EVERY trap entry at the very beginning
    uart.puts("[TRAP] Entry - scause: 0x");
    uart.putHex(scause_val);
    uart.puts(" stval: 0x");
    uart.putHex(stval_val);
    uart.puts(" sepc: 0x");
    uart.putHex(sepc_val);
    uart.puts("\n");

    // Additional debug: Show current process info
    if (proc.Scheduler.getCurrentProcess()) |current| {
        uart.puts("  Current process: pid=");
        uart.putHex(current.pid);
        uart.puts(", state=");
        switch (current.state) {
            .UNUSED => uart.puts("UNUSED"),
            .EMBRYO => uart.puts("EMBRYO"),
            .RUNNABLE => uart.puts("RUNNABLE"),
            .RUNNING => uart.puts("RUNNING"),
            .SLEEPING => uart.puts("SLEEPING"),
            .ZOMBIE => uart.puts("ZOMBIE"),
        }
        uart.puts("\n");
    }

    // CRITICAL DEBUG: Check if user page table L2 PTE is still valid
    const current_satp = csr.readSatp();
    const current_ppn = current_satp & 0xFFFFFFFFFFF;
    if (current_ppn == 0x802bf) {
        const root_addr = current_ppn << 12;
        const root_table = @as([*]const volatile u64, @ptrFromInt(root_addr));
        const vpn2 = (0x8021b000 >> 30) & 0x1FF;
        const l2_pte = root_table[vpn2];

        // Force memory barrier
        asm volatile ("fence rw, rw" ::: "memory");

        if (l2_pte == 0) {
            uart.puts("[TRAP] CRITICAL: L2 PTE is already ZERO on trap entry!\n");
            uart.puts("  This trap: scause=0x");
            uart.putHex(scause_val);
            uart.puts(", sepc=0x");
            uart.putHex(sepc_val);
            uart.puts("\n");
            uart.puts("  First corruption detected at this trap!\n");

            // Check surrounding PTEs to see if it's just one entry or broader corruption
            uart.puts("  Checking neighboring L2 PTEs:\n");
            if (vpn2 > 0) {
                uart.puts("    PTE[");
                uart.putHex(vpn2 - 1);
                uart.puts("] = 0x");
                uart.putHex(root_table[vpn2 - 1]);
                uart.puts("\n");
            }
            uart.puts("    PTE[");
            uart.putHex(vpn2);
            uart.puts("] = 0x");
            uart.putHex(root_table[vpn2]);
            uart.puts(" <- CORRUPTED\n");
            if (vpn2 < 511) {
                uart.puts("    PTE[");
                uart.putHex(vpn2 + 1);
                uart.puts("] = 0x");
                uart.putHex(root_table[vpn2 + 1]);
                uart.puts("\n");
            }
        } else {
            // PTE is still valid
            if ((scause_val & (1 << 63)) != 0) {
                // This is an interrupt
                uart.puts("[TRAP] L2 PTE still valid (0x");
                uart.putHex(l2_pte);
                uart.puts(") during interrupt\n");
            }
        }
    }

    const cause = frame.scause;
    const is_interrupt = (cause & (1 << 63)) != 0;
    const exception_code = cause & 0x7FFFFFFFFFFFFFFF;

    // Debug: Show trap type
    if (is_interrupt) {
        uart.puts("[TRAP] INTERRUPT - code: ");
        uart.putHex(exception_code);
        uart.puts("\n");
    } else {
        uart.puts("[TRAP] EXCEPTION - code: ");
        uart.putHex(exception_code);
        uart.puts("\n");
    }

    // Debug: Show we reached trap handler successfully (only for non-syscall and non-external-interrupt traps)
    const is_syscall = (!is_interrupt) and (exception_code == @intFromEnum(ExceptionCause.EcallFromUMode));
    const is_external_int = is_interrupt and (exception_code == 9); // Supervisor external interrupt
    if (!is_syscall and !is_external_int) {}

    if (is_interrupt) {
        // Handle interrupts
        checkPTECorruption("Before interruptHandler");

        // Extra check for UART interrupts
        if (exception_code == 9) { // External interrupt
            checkPTECorruption("Before external interrupt (UART)");
        }

        interruptHandler(frame, exception_code);

        if (exception_code == 9) {
            checkPTECorruption("After external interrupt (UART)");
        }

        checkPTECorruption("After interruptHandler");
    } else {
        // Handle exceptions
        checkPTECorruption("Before exceptionHandler");
        exceptionHandler(frame, exception_code);
        checkPTECorruption("After exceptionHandler");
    }

    // Final check before returning to user/kernel mode
    checkPTECorruption("End of trapHandler");

    // CRITICAL: Verify current SATP has kernel mappings before returning
    const final_satp = csr.readSatp();
    const final_ppn = final_satp & 0xFFFFFFFFFFF;

    // Check if this is a user page table that might lack kernel mappings
    if (final_ppn != memory.kernel_page_table.root_ppn and final_ppn != 0) {
        // This is a user page table - verify it has kernel code mapped
        const root_addr = final_ppn << 12;
        const root_table = @as([*]const volatile u64, @ptrFromInt(root_addr));
        const vpn2_for_kernel = (0x80200000 >> 30) & 0x1FF; // Check kernel code start
        const l2_pte = root_table[vpn2_for_kernel];

        if (l2_pte == 0) {
            uart.puts("[TRAP] FATAL: About to return with page table lacking kernel mappings!\n");
            uart.puts("  SATP: 0x");
            uart.putHex(final_satp);
            uart.puts(", PPN: 0x");
            uart.putHex(final_ppn);
            uart.puts("\n  This will cause immediate page fault!\n");

            // Switch to kernel page table as emergency measure
            uart.puts("  EMERGENCY: Switching to kernel page table\n");
            const kernel_satp = csr.SATP_SV39 | memory.kernel_page_table.root_ppn;
            csr.writeSatp(kernel_satp);
            csr.sfence_vma();

            // Update process context too
            if (proc.Scheduler.getCurrentProcess()) |current| {
                current.context.satp = kernel_satp;
            }
        }
    }

    // CRITICAL FIX: Check if we're about to return to kernel code with user privilege
    // This happens when a syscall sleeps and then wakes up
    const final_sstatus = csr.readSstatus();
    const final_spp = (final_sstatus >> 8) & 1;
    if (final_spp == 0 and frame.sepc >= 0x80000000) {
        // About to return to kernel code with user privilege - fix it!
        uart.puts("[TRAP] CRITICAL: Fixing SPP before return to kernel code\n");
        uart.puts("  sepc=0x");
        uart.putHex(frame.sepc);
        uart.puts(" SPP=");
        uart.putHex(final_spp);
        uart.puts("\n");

        // Set SPP=1 to return to supervisor mode
        const fixed_sstatus = final_sstatus | (1 << 8);
        csr.writeSstatus(fixed_sstatus);
        uart.puts("  Fixed SPP=1 for supervisor return\n");
    }
}

fn interruptHandler(frame: *TrapFrame, code: u64) void {
    _ = frame;
    uart.puts("[INTERRUPT] Handler called with code: ");
    uart.putHex(code);
    uart.puts("\n");

    switch (code) {
        csr.Interrupt.SupervisorExternal => {
            uart.puts("[INTERRUPT] Supervisor External Interrupt detected!\n");
            // Handle external interrupt via PLIC
            handlePLICInterrupt();
        },
        else => {
            uart.puts("[INTERRUPT] Unknown interrupt code: ");
            uart.putHex(code);
            uart.puts("\n");
        },
    }
}

fn handlePLICInterrupt() void {
    uart.puts("[PLIC] Handling PLIC interrupt\n");

    // PLIC addresses
    const PLIC_BASE: u64 = 0x0c000000;
    // Hart 0, Context 1 (S-mode) claim/complete register
    const PLIC_CLAIM = PLIC_BASE + 0x201004; // This is the correct address for hart 0, context 1

    // Claim the interrupt
    const claim_addr = @as(*volatile u32, @ptrFromInt(PLIC_CLAIM));
    const irq = claim_addr.*;

    uart.puts("[PLIC] Claimed IRQ: ");
    uart.putHex(irq);
    uart.puts("\n");

    if (irq == 10) { // UART IRQ
        uart.puts("[PLIC] UART IRQ 10 detected! Calling uartIsr()\n");
        file.uartIsr();

        // Complete the interrupt
        claim_addr.* = irq;
        uart.puts("[PLIC] UART IRQ completed\n");
    } else if (irq != 0) {
        uart.puts("[PLIC] Unknown IRQ: ");
        uart.putHex(irq);
        uart.puts("\n");

        // Complete the interrupt anyway
        claim_addr.* = irq;
    } else {
        uart.puts("[PLIC] Spurious interrupt (IRQ 0)\n");
    }
}

fn handlePageFault(frame: *TrapFrame, code: u64) void {
    const fault_addr = frame.stval;
    const fault_type = switch (code) {
        @intFromEnum(ExceptionCause.InstructionPageFault) => "Instruction",
        @intFromEnum(ExceptionCause.LoadPageFault) => "Load",
        @intFromEnum(ExceptionCause.StorePageFault) => "Store",
        else => "Unknown",
    };

    // Detailed page fault debugging
    uart.puts("\n=============== PAGE FAULT DETAILS ===============\n");
    uart.puts("[PAGE_FAULT] Type: ");
    uart.puts(fault_type);
    uart.puts(" Page Fault (code ");
    uart.putHex(code);
    uart.puts(")\n");

    uart.puts("[PAGE_FAULT] Faulting address (stval): 0x");
    uart.putHex(fault_addr);
    uart.puts("\n");

    uart.puts("[PAGE_FAULT] Fault occurred at PC (sepc): 0x");
    uart.putHex(frame.sepc);
    uart.puts("\n");

    uart.puts("[PAGE_FAULT] Stack pointer (sp): 0x");
    uart.putHex(frame.sp);
    uart.puts("\n");

    // Determine if this is a kernel or user address
    const is_kernel_addr = fault_addr >= 0x80000000;
    uart.puts("[PAGE_FAULT] Address space: ");
    if (is_kernel_addr) {
        uart.puts("KERNEL (>= 0x80000000)\n");
    } else {
        uart.puts("USER (< 0x80000000)\n");
    }

    // Get current process information
    if (proc.Scheduler.getCurrentProcess()) |current| {
        uart.puts("[PAGE_FAULT] Current process PID: ");
        uart.putHex(@intCast(current.pid));
        uart.puts("\n");

        uart.puts("[PAGE_FAULT] Process state: ");
        switch (current.state) {
            .UNUSED => uart.puts("UNUSED"),
            .EMBRYO => uart.puts("EMBRYO"),
            .RUNNABLE => uart.puts("RUNNABLE"),
            .RUNNING => uart.puts("RUNNING"),
            .SLEEPING => uart.puts("SLEEPING"),
            .ZOMBIE => uart.puts("ZOMBIE"),
        }
        uart.puts("\n");

        // Show if this happened right after waking from sleep
        if (current.state == .RUNNING) {
            uart.puts("[PAGE_FAULT] Process is currently RUNNING\n");
        }
    } else {
        uart.puts("[PAGE_FAULT] No current process!\n");
    }

    // Additional register dump for debugging
    uart.puts("[PAGE_FAULT] Register dump:\n");
    uart.puts("  ra: 0x");
    uart.putHex(frame.ra);
    uart.puts("\n");
    uart.puts("  a0: 0x");
    uart.putHex(frame.a0);
    uart.puts("\n");
    uart.puts("  a1: 0x");
    uart.putHex(frame.a1);
    uart.puts("\n");
    uart.puts("  a2: 0x");
    uart.putHex(frame.a2);
    uart.puts("\n");
    uart.puts("  a3: 0x");
    uart.putHex(frame.a3);
    uart.puts("\n");

    // Show satp register value to debug page table issues
    const satp = csr.readSatp();
    uart.puts("[PAGE_FAULT] satp register: 0x");
    uart.putHex(satp);
    uart.puts("\n");

    const mode = (satp >> 60) & 0xF;
    const asid = (satp >> 44) & 0xFFFF;
    const ppn = satp & 0xFFFFFFFFFFF;

    uart.puts("[PAGE_FAULT] satp breakdown:\n");
    uart.puts("  Mode: ");
    uart.putHex(mode);
    uart.puts(" (8=Sv39, 9=Sv48)\n");
    uart.puts("  ASID: ");
    uart.putHex(asid);
    uart.puts("\n");
    uart.puts("  Root page table PPN: 0x");
    uart.putHex(ppn);
    uart.puts("\n");
    uart.puts("  Root page table physical addr: 0x");
    uart.putHex(ppn << 12);
    uart.puts("\n");

    // Check if the faulting address is actually mapped
    uart.puts("\n[PAGE_FAULT] Checking kernel page table mapping...\n");

    // Compare current SATP with kernel page table
    uart.puts("  kernel_page_table.root_ppn: 0x");
    uart.putHex(memory.kernel_page_table.root_ppn);
    uart.puts("\n");
    uart.puts("  Current SATP root_ppn: 0x");
    uart.putHex(ppn);
    if (memory.kernel_page_table.root_ppn == ppn) {
        uart.puts(" (MATCH)\n");
    } else {
        uart.puts(" (MISMATCH!)\n");
    }

    if (memory.kernel_page_table.translate(fault_addr)) |phys_addr| {
        uart.puts("  Virtual 0x");
        uart.putHex(fault_addr);
        uart.puts(" -> Physical 0x");
        uart.putHex(phys_addr);
        uart.puts(" (MAPPED in kernel_page_table)\n");

        // Try to check the actual PTE flags - do complete walk
        const va_vpn = fault_addr >> 12;

        // DEBUG: Show the calculation step by step
        uart.puts("  VPN calculation for 0x");
        uart.putHex(fault_addr);
        uart.puts(":\n");
        uart.puts("    fault_addr >> 12 = 0x");
        uart.putHex(va_vpn);
        uart.puts("\n");
        uart.puts("    va_vpn >> 18 = 0x");
        uart.putHex(va_vpn >> 18);
        uart.puts("\n");
        uart.puts("    (va_vpn >> 18) & 0x1FF = 0x");
        uart.putHex((va_vpn >> 18) & 0x1FF);
        uart.puts("\n");

        // Calculate VPNs directly to avoid array indexing issues
        const vpn2 = (fault_addr >> 30) & 0x1FF;
        const vpn1 = (fault_addr >> 21) & 0x1FF;
        const vpn0 = (fault_addr >> 12) & 0x1FF;

        uart.puts("  Direct VPN calculation:\n");
        uart.puts("    fault_addr=0x");
        uart.putHex(fault_addr);
        uart.puts("\n");
        uart.puts("    VPN[2]=(addr>>30)&0x1FF=0x");
        uart.putHex(vpn2);
        uart.puts("\n");
        uart.puts("    VPN[1]=(addr>>21)&0x1FF=0x");
        uart.putHex(vpn1);
        uart.puts("\n");
        uart.puts("    VPN[0]=(addr>>12)&0x1FF=0x");
        uart.putHex(vpn0);
        uart.puts("\n");

        uart.puts("  Page table walk for VA 0x");
        uart.putHex(fault_addr);
        uart.puts(":\n");
        uart.puts("    Using VPN[2]=");
        uart.putHex(vpn2);
        uart.puts(", VPN[1]=");
        uart.putHex(vpn1);
        uart.puts(", VPN[0]=");
        uart.putHex(vpn0);
        uart.puts("\n");

        // Walk the page table to check permissions
        var table_addr = ppn << 12;

        // Level 2 (root)
        var pte_addr = table_addr + @as(usize, vpn2) * 8;
        var pte_ptr = @as(*const volatile u64, @ptrFromInt(pte_addr));
        var pte = pte_ptr.*;

        uart.puts("  L2 PTE at 0x");
        uart.putHex(pte_addr);
        uart.puts(" = 0x");
        uart.putHex(pte);
        if ((pte & 1) != 0) {
            uart.puts(" (V)\n");
            // Level 1
            table_addr = ((pte >> 10) & 0xFFFFFFFFFFF) << 12;
            pte_addr = table_addr + @as(usize, vpn1) * 8;
            pte_ptr = @as(*const volatile u64, @ptrFromInt(pte_addr));
            pte = pte_ptr.*;

            uart.puts("  L1 PTE at 0x");
            uart.putHex(pte_addr);
            uart.puts(" = 0x");
            uart.putHex(pte);
            if ((pte & 1) != 0) {
                uart.puts(" (V");
                if ((pte & 2) != 0) uart.puts("R");
                if ((pte & 4) != 0) uart.puts("W");
                if ((pte & 8) != 0) uart.puts("X");
                uart.puts(")\n");

                // Check if leaf or need L0
                if ((pte & 0xE) == 0) {
                    // Non-leaf, go to L0
                    table_addr = ((pte >> 10) & 0xFFFFFFFFFFF) << 12;
                    pte_addr = table_addr + @as(usize, vpn0) * 8;
                    pte_ptr = @as(*const volatile u64, @ptrFromInt(pte_addr));
                    pte = pte_ptr.*;

                    uart.puts("  L0 PTE at 0x");
                    uart.putHex(pte_addr);
                    uart.puts(" = 0x");
                    uart.putHex(pte);
                    if ((pte & 1) != 0) {
                        uart.puts(" (V");
                        if ((pte & 2) != 0) uart.puts("R");
                        if ((pte & 4) != 0) uart.puts("W");
                        if ((pte & 8) != 0) uart.puts("X");
                        if ((pte & 0x10) != 0) uart.puts("U");
                        uart.puts(")\n");

                        // Check if permissions are correct for kernel code
                        if (is_kernel_addr and (pte & 0x8) != 0) {
                            uart.puts("  Kernel code IS mapped and executable!\n");
                        }
                    } else {
                        uart.puts(" (INVALID!)\n");
                    }
                }
            } else {
                uart.puts(" (INVALID!)\n");
            }
        } else {
            uart.puts(" (INVALID!)\n");
        }
    } else {
        uart.puts("  Virtual 0x");
        uart.putHex(fault_addr);
        uart.puts(" -> NOT MAPPED!\n");
    }

    uart.puts("==================================================\n\n");

    // Calculate VPNs for later use
    const fault_vpn2 = (fault_addr >> 30) & 0x1FF;
    const fault_vpn1 = (fault_addr >> 21) & 0x1FF;
    const fault_vpn0 = (fault_addr >> 12) & 0x1FF;

    // Check if this is a kernel code fault with user page table
    const is_kernel_fault = fault_addr >= 0x80000000;
    const is_instruction_fault = (code == @intFromEnum(ExceptionCause.InstructionPageFault));
    const wrong_page_table = (ppn != memory.kernel_page_table.root_ppn);

    // CRITICAL: Check if we found valid mappings in the page walk
    var found_valid_mapping = false;
    if (ppn != 0) {
        // We did a page walk - check if we found a valid executable PTE
        const root_addr = ppn << 12;
        const root_table = @as([*]const volatile u64, @ptrFromInt(root_addr));
        const l2_pte = root_table[fault_vpn2];
        if ((l2_pte & 1) != 0) {
            // L2 is valid, check deeper
            const l1_addr = ((l2_pte >> 10) & 0xFFFFFFFFFFF) << 12;
            const l1_table = @as([*]const volatile u64, @ptrFromInt(l1_addr));
            const l1_pte = l1_table[fault_vpn1];
            if ((l1_pte & 1) != 0) {
                // L1 is valid, check L0
                const l0_addr = ((l1_pte >> 10) & 0xFFFFFFFFFFF) << 12;
                const l0_table = @as([*]const volatile u64, @ptrFromInt(l0_addr));
                const l0_pte = l0_table[fault_vpn0];
                if ((l0_pte & 0xF) == 0xF) { // Valid + RWX
                    found_valid_mapping = true;
                }
            }
        }
    }

    if (is_kernel_fault and is_instruction_fault and wrong_page_table and !found_valid_mapping) {
        uart.puts("[PAGE_FAULT] FATAL: Kernel code fault with user page table\n");
        uart.puts("[PAGE_FAULT] This indicates buildKernelGlobalMappings() failed!\n");
        uart.puts("[PAGE_FAULT] User page table PPN: 0x");
        uart.putHex(ppn);
        uart.puts("\n[PAGE_FAULT] Kernel page table PPN: 0x");
        uart.putHex(memory.kernel_page_table.root_ppn);
        uart.puts("\n[PAGE_FAULT] This is a critical error - user PT missing kernel mappings\n");
    } else if (found_valid_mapping) {
        uart.puts("[PAGE_FAULT] ERROR: Page table has valid mapping but still faulted!\n");
        uart.puts("  This suggests:\n");
        uart.puts("  - Permission issue (User bit set on kernel page?)\n");
        uart.puts("  - TLB not flushed properly\n");
        uart.puts("  - Hardware/emulator bug\n");

        // Check the actual PTE flags
        const root_addr = ppn << 12;
        const root_table = @as([*]const volatile u64, @ptrFromInt(root_addr));
        const l2_pte = root_table[fault_vpn2];
        const l1_addr = ((l2_pte >> 10) & 0xFFFFFFFFFFF) << 12;
        const l1_table = @as([*]const volatile u64, @ptrFromInt(l1_addr));
        const l1_pte = l1_table[fault_vpn1];
        const l0_addr = ((l1_pte >> 10) & 0xFFFFFFFFFFF) << 12;
        const l0_table = @as([*]const volatile u64, @ptrFromInt(l0_addr));
        const l0_pte = l0_table[fault_vpn0];

        uart.puts("\n  L0 PTE flags analysis:\n");
        uart.puts("    V=");
        uart.putHex((l0_pte >> 0) & 1);
        uart.puts(" R=");
        uart.putHex((l0_pte >> 1) & 1);
        uart.puts(" W=");
        uart.putHex((l0_pte >> 2) & 1);
        uart.puts(" X=");
        uart.putHex((l0_pte >> 3) & 1);
        uart.puts(" U=");
        uart.putHex((l0_pte >> 4) & 1);
        uart.puts(" G=");
        uart.putHex((l0_pte >> 5) & 1);
        uart.puts(" A=");
        uart.putHex((l0_pte >> 6) & 1);
        uart.puts(" D=");
        uart.putHex((l0_pte >> 7) & 1);
        uart.puts("\n");

        if ((l0_pte & 0x10) != 0) {
            uart.puts("  WARNING: User bit is set on kernel page!\n");
        }
    }

    // Check current privilege mode
    const sstatus = csr.readSstatus();
    const spp_bit = (sstatus >> 8) & 1; // SPP bit indicates previous privilege
    uart.puts("[PAGE_FAULT] Current sstatus: 0x");
    uart.putHex(sstatus);
    uart.puts("\n[PAGE_FAULT] SPP bit (previous privilege): ");
    uart.putHex(spp_bit);
    if (spp_bit == 0) {
        uart.puts(" (User mode)\n");
    } else {
        uart.puts(" (Supervisor mode)\n");
    }

    // Check if we're trying to execute supervisor code from user mode
    if (found_valid_mapping and is_kernel_addr and is_instruction_fault and spp_bit == 0) {
        uart.puts("[PAGE_FAULT] CRITICAL: Trying to execute supervisor code from user mode!\n");
        uart.puts("[PAGE_FAULT] This is a privilege violation, not a mapping issue.\n");
        uart.puts("[PAGE_FAULT] The read syscall needs to complete in supervisor mode.\n");

        // This is a fundamental issue - we can't fix it with TLB flushes
        // The context switch restored the wrong privilege level
        uart.puts("[PAGE_FAULT] Context switch bug: Lost supervisor mode during sleep/wake\n");
        // Don't retry - this won't help
    } else if (found_valid_mapping) {
        // Check if this is the same fault address
        if (fault_addr == last_fault_addr) {
            tlb_retry_count += 1;
        } else {
            // New fault address, reset counter
            tlb_retry_count = 1;
            last_fault_addr = fault_addr;
        }

        // Limit retries to prevent infinite loops
        if (tlb_retry_count > 3) {
            uart.puts("[PAGE_FAULT] ERROR: TLB retry limit exceeded (");
            uart.putHex(tlb_retry_count);
            uart.puts(" attempts)\n");
            uart.puts("[PAGE_FAULT] Valid mapping exists but CPU keeps faulting.\n");
            uart.puts("[PAGE_FAULT] This indicates a hardware bug or emulator issue.\n");
            // Fall through to halt
        } else {
            uart.puts("[PAGE_FAULT] CRITICAL: Found valid mapping but still faulted!\n");
            uart.puts("[PAGE_FAULT] This is likely a TLB consistency issue.\n");
            uart.puts("[PAGE_FAULT] Retry attempt ");
            uart.putHex(tlb_retry_count);
            uart.puts(" of 3\n");
            uart.puts("[PAGE_FAULT] Attempting comprehensive TLB flush...\n");

            // Flush entire TLB
            csr.sfence_vma();

            // Also try flushing just this specific address
            asm volatile ("sfence.vma %[addr], zero"
                :
                : [addr] "r" (fault_addr),
                : "memory"
            );

            // Add memory barrier
            asm volatile ("fence.i" ::: "memory");
            asm volatile ("fence rw, rw" ::: "memory");

            uart.puts("[PAGE_FAULT] TLB flushed. Returning to retry instruction at 0x");
            uart.putHex(frame.sepc);
            uart.puts("\n");

            // Return without incrementing sepc to retry the same instruction
            return;
        }
    }

    // Halt the system after printing debug info
    uart.puts("[PAGE_FAULT] Halting system due to unhandled page fault\n");
    while (true) {
        csr.wfi();
    }
}

fn exceptionHandler(frame: *TrapFrame, code: u64) void {
    switch (code) {
        @intFromEnum(ExceptionCause.EcallFromUMode) => {
            syscallHandler(frame);
            // Skip ecall instruction
            frame.sepc += 4;
        },
        @intFromEnum(ExceptionCause.InstructionPageFault), @intFromEnum(ExceptionCause.LoadPageFault), @intFromEnum(ExceptionCause.StorePageFault) => {
            handlePageFault(frame, code);
        },
        else => {
            uart.puts("[EXCEPTION] Unhandled exception code: ");
            uart.putHex(code);
            uart.puts("\n");

            // Stop infinite loop - halt system
            while (true) {
                csr.wfi();
            }
        },
    }
}

// System call handler using full dispatcher
fn syscallHandler(frame: *TrapFrame) void {
    const syscall_num = frame.a7;

    // Get and validate current process
    const current = proc.Scheduler.getCurrentProcess() orelse {
        // No current process - return error without debug output
        frame.a0 = @bitCast(@as(isize, defs.ESRCH));
        return;
    };

    // Associate trap frame with current process
    current.user_frame = frame;

    // CRITICAL: Update process's kernel context SATP to match current SATP
    // This ensures context switches preserve the correct page table
    const current_satp = csr.readSatp();
    if (current.context.satp != current_satp) {
        uart.puts("[SYSCALL] Updating process context SATP from 0x");
        uart.putHex(current.context.satp);
        uart.puts(" to 0x");
        uart.putHex(current_satp);
        uart.puts("\n");
        current.context.satp = current_satp;
    }

    // Only show syscall debug for non-repetitive calls (not read/write in shell loop)
    const is_shell_io = (syscall_num == 1) or (syscall_num == 0x3f) or (syscall_num == 0x40); // write or read
    if (!is_shell_io) {}

    // Use full dispatcher
    const result = dispatch.call(syscall_num, frame.a0, frame.a1, frame.a2, frame.a3, frame.a4);
    frame.a0 = @bitCast(result);
}
