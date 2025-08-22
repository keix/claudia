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

// Main trap handler called from assembly
pub export fn trapHandler(frame: *TrapFrame) void {
    const cause = frame.scause;
    const is_interrupt = (cause & (1 << 63)) != 0;
    const exception_code = cause & 0x7FFFFFFFFFFFFFFF;

    // Debug: Show we reached trap handler successfully (only for non-syscall and non-external-interrupt traps)
    const is_syscall = (!is_interrupt) and (exception_code == @intFromEnum(ExceptionCause.EcallFromUMode));
    const is_external_int = is_interrupt and (exception_code == 9); // Supervisor external interrupt
    if (!is_syscall and !is_external_int) {
    }

    if (is_interrupt) {
        // Handle interrupts
        interruptHandler(frame, exception_code);
    } else {
        // Handle exceptions
        exceptionHandler(frame, exception_code);
    }
}

fn interruptHandler(frame: *TrapFrame, code: u64) void {
    _ = frame;
    switch (code) {
        csr.Interrupt.SupervisorExternal => {
            // Handle external interrupt via PLIC
            handlePLICInterrupt();
        },
        else => {
        },
    }
}

fn handlePLICInterrupt() void {
    // PLIC addresses
    const PLIC_BASE: u64 = 0x0c000000;
    // Hart 0, Context 1 (S-mode) claim/complete register
    const PLIC_CLAIM = PLIC_BASE + 0x201004; // This is the correct address for hart 0, context 1

    // Claim the interrupt
    const claim_addr = @as(*volatile u32, @ptrFromInt(PLIC_CLAIM));
    const irq = claim_addr.*;

    if (irq == 10) { // UART IRQ
        file.uartIsr();

        // Complete the interrupt
        claim_addr.* = irq;
    } else if (irq != 0) {

        // Complete the interrupt anyway
        claim_addr.* = irq;
    }
}

fn exceptionHandler(frame: *TrapFrame, code: u64) void {
    switch (code) {
        @intFromEnum(ExceptionCause.EcallFromUMode) => {
            syscallHandler(frame);
            // Skip ecall instruction
            frame.sepc += 4;
        },
        else => {

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

    // Only show syscall debug for non-repetitive calls (not read/write in shell loop)
    const is_shell_io = (syscall_num == 1) or (syscall_num == 0x3f) or (syscall_num == 0x40); // write or read
    if (!is_shell_io) {
    }

    // Use full dispatcher
    const result = dispatch.call(syscall_num, frame.a0, frame.a1, frame.a2, frame.a3, frame.a4);
    frame.a0 = @bitCast(result);
}
