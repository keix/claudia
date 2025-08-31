// Trap handling for RISC-V
// Manages system calls and exceptions from user mode

const csr = @import("../arch/riscv/csr.zig");
const proc = @import("../process/core.zig");
const file = @import("../file/core.zig");
const abi = @import("abi");
const defs = abi;
const dispatch = @import("../syscalls/dispatch.zig");
const memory = @import("../memory/core.zig");
const config = @import("../config.zig");

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

// TLB retry state for handling stale entries
const TlbRetryState = struct {
    retry_count: u32 = 0,
    last_fault_addr: u64 = 0,

    fn shouldRetry(self: *TlbRetryState, fault_addr: u64) bool {
        if (fault_addr == self.last_fault_addr) {
            self.retry_count += 1;
        } else {
            // New fault address, reset counter
            self.retry_count = 1;
            self.last_fault_addr = fault_addr;
        }

        return self.retry_count <= config.PageTable.MAX_TLB_RETRY_ATTEMPTS;
    }

    fn performTlbFlush(fault_addr: u64) void {
        // Flush entire TLB
        csr.sfence_vma();

        // Also try flushing just this specific address
        asm volatile ("sfence.vma %[addr], zero"
            :
            : [addr] "r" (fault_addr),
            : "memory"
        );

        // Add memory barriers
        asm volatile ("fence.i" ::: "memory");
        asm volatile ("fence rw, rw" ::: "memory");
    }
};

var tlb_retry_state = TlbRetryState{};

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

    // Set open function separately
    const fs = @import("../syscalls/fs.zig");
    fs.setOpenFn(fileOpen);
}

// File system function wrappers for dispatcher
fn fileGetFile(fd: i32) ?*anyopaque {
    const result = file.FileTable.getFile(fd);
    return @as(?*anyopaque, @ptrCast(result));
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

fn fileOpen(path: []const u8, flags: u32, mode: u16) isize {
    return file.FileTable.sysOpen(path, flags, mode);
}

// Main trap handler called from assembly
pub export fn trapHandler(frame: *TrapFrame) void {
    const cause = frame.scause;
    const is_interrupt = (cause & (1 << 63)) != 0;
    const exception_code = cause & 0x7FFFFFFFFFFFFFFF;

    if (is_interrupt) {
        // Handle interrupts
        interruptHandler(frame, exception_code);
    } else {
        // Handle exceptions
        exceptionHandler(frame, exception_code);
    }

    const final_satp = csr.readSatp();
    const final_ppn = final_satp & 0xFFFFFFFFFFF;

    if (final_ppn != memory.kernel_page_table.root_ppn and final_ppn != 0) {
        const root_addr = final_ppn << 12;
        const root_table = @as([*]const volatile u64, @ptrFromInt(root_addr));
        const vpn2_for_kernel = (0x80200000 >> 30) & 0x1FF;
        const l2_pte = root_table[vpn2_for_kernel];

        if (l2_pte == 0) {
            const kernel_satp = csr.SATP_SV39 | memory.kernel_page_table.root_ppn;
            csr.writeSatp(kernel_satp);
            csr.sfence_vma();

            if (proc.Scheduler.getCurrentProcess()) |current| {
                current.context.satp = kernel_satp;
            }
        }
    }

    const final_sstatus = csr.readSstatus();
    const final_spp = (final_sstatus >> 8) & 1;
    if (final_spp == 0 and frame.sepc >= config.MemoryLayout.USER_KERNEL_BOUNDARY) {
        const fixed_sstatus = final_sstatus | (1 << 8);
        csr.writeSstatus(fixed_sstatus);
    }
}

fn interruptHandler(frame: *TrapFrame, code: u64) void {
    _ = frame;
    switch (code) {
        csr.Interrupt.SupervisorTimer => {
            const timer = @import("../time/timer.zig");
            timer.checkSleepers();
        },
        csr.Interrupt.SupervisorExternal => {
            handlePLICInterrupt();
        },
        else => {},
    }
}

fn handlePLICInterrupt() void {
    const plic = @import("../driver/plic.zig");

    // Claim the interrupt (hart 0, context 1 for S-mode)
    const irq = plic.claim(0, 1);

    if (irq == plic.IRQ.UART0) {
        file.uartIsr();
    }

    // Complete the interrupt if one was claimed
    if (irq != 0) {
        plic.complete(0, 1, irq);
    }
}

fn handlePageFault(frame: *TrapFrame, code: u64) void {
    const fault_addr = frame.stval;
    const is_kernel_addr = fault_addr >= config.MemoryLayout.USER_KERNEL_BOUNDARY;
    const satp = csr.readSatp();
    const ppn = satp & 0xFFFFFFFFFFF;
    const fault_vpn2 = (fault_addr >> 30) & 0x1FF;
    const fault_vpn1 = (fault_addr >> 21) & 0x1FF;
    const fault_vpn0 = (fault_addr >> 12) & 0x1FF;
    const is_instruction_fault = (code == @intFromEnum(ExceptionCause.InstructionPageFault));

    var found_valid_mapping = false;
    if (ppn != 0) {
        const root_addr = ppn << 12;
        const root_table = @as([*]const volatile u64, @ptrFromInt(root_addr));
        const l2_pte = root_table[fault_vpn2];
        if ((l2_pte & 1) != 0) {
            const l1_addr = ((l2_pte >> 10) & 0xFFFFFFFFFFF) << 12;
            const l1_table = @as([*]const volatile u64, @ptrFromInt(l1_addr));
            const l1_pte = l1_table[fault_vpn1];
            if ((l1_pte & 1) != 0) {
                const l0_addr = ((l1_pte >> 10) & 0xFFFFFFFFFFF) << 12;
                const l0_table = @as([*]const volatile u64, @ptrFromInt(l0_addr));
                const l0_pte = l0_table[fault_vpn0];
                if ((l0_pte & 0xF) == 0xF) { // Valid + RWX
                    found_valid_mapping = true;
                }
            }
        }
    }

    const sstatus2 = csr.readSstatus();
    const spp_bit = (sstatus2 >> 8) & 1;

    if (found_valid_mapping and is_kernel_addr and is_instruction_fault and spp_bit == 0) {
        // Fundamental issue - context switch restored wrong privilege level
    } else if (found_valid_mapping and tlb_retry_state.shouldRetry(fault_addr)) {
        TlbRetryState.performTlbFlush(fault_addr);
        return; // Retry same instruction
    }

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
            while (true) {
                csr.wfi();
            }
        },
    }
}

// System call handler using full dispatcher
fn syscallHandler(frame: *TrapFrame) void {
    const syscall_num = frame.a7;

    const current = proc.Scheduler.getCurrentProcess() orelse {
        frame.a0 = @bitCast(@as(isize, defs.ESRCH));
        return;
    };

    // Associate trap frame with current process
    current.user_frame = frame;

    const current_satp = csr.readSatp();
    if (current.context.satp != current_satp) {
        current.context.satp = current_satp;
    }

    // Use full dispatcher
    const result = dispatch.call(syscall_num, frame.a0, frame.a1, frame.a2, frame.a3, frame.a4);
    frame.a0 = @bitCast(result);
}
