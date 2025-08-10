// Trap handling for RISC-V
// Manages system calls and exceptions from user mode

const std = @import("std");
const csr = @import("../arch/riscv/csr.zig");
const uart = @import("../driver/uart/core.zig");
const proc = @import("../process/core.zig");
const file = @import("../file/core.zig");

// Import trap vector from assembly
extern const trap_vector: u8;

// Trap frame structure matching the assembly layout
pub const TrapFrame = struct {
    epc: u64,      // 0: Exception program counter
    ra: u64,       // 8: Return address (x1)
    gp: u64,       // 16: Global pointer (x3)
    tp: u64,       // 24: Thread pointer (x4)
    t0: u64,       // 32: Temporary (x5)
    t1: u64,       // 40: Temporary (x6)
    t2: u64,       // 48: Temporary (x7)
    s0: u64,       // 56: Saved register (x8)
    s1: u64,       // 64: Saved register (x9)
    a0: u64,       // 72: Function argument/return value (x10)
    a1: u64,       // 80: Function argument (x11)
    a2: u64,       // 88: Function argument (x12)
    a3: u64,       // 96: Function argument (x13)
    a4: u64,       // 104: Function argument (x14)
    a5: u64,       // 112: Function argument (x15)
    a6: u64,       // 120: Function argument (x16)
    a7: u64,       // 128: Function argument/syscall number (x17)
    s2: u64,       // 136: Saved register (x18)
    s3: u64,       // 144: Saved register (x19)
    s4: u64,       // 152: Saved register (x20)
    s5: u64,       // 160: Saved register (x21)
    s6: u64,       // 168: Saved register (x22)
    s7: u64,       // 176: Saved register (x23)
    s8: u64,       // 184: Saved register (x24)
    s9: u64,       // 192: Saved register (x25)
    s10: u64,      // 200: Saved register (x26)
    s11: u64,      // 208: Saved register (x27)
    t3: u64,       // 216: Temporary (x28)
    t4: u64,       // 224: Temporary (x29)
    t5: u64,       // 232: Temporary (x30)
    t6: u64,       // 240: Temporary (x31)
    sp: u64,       // 248: Stack pointer (x2)
    cause: u64,    // 256: Trap cause
    tval: u64,     // 264: Trap value
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
    uart.puts("[trap] Initializing trap handler\n");
    
    // Set trap vector
    const trap_vector_addr = @intFromPtr(&trap_vector);
    csr.writeStvec(trap_vector_addr);
    
    uart.puts("[trap] Trap vector set to: ");
    uart.putHex(trap_vector_addr);
    uart.puts("\n");
}

// Main trap handler called from assembly
pub export fn trapHandler(frame: *TrapFrame) void {
    const cause = frame.cause;
    const is_interrupt = (cause & (1 << 63)) != 0;
    const exception_code = cause & 0x7FFFFFFFFFFFFFFF;
    
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
    uart.puts("[trap] Unhandled interrupt: ");
    uart.putHex(code);
    uart.puts("\n");
}

fn exceptionHandler(frame: *TrapFrame, code: u64) void {
    switch (code) {
        @intFromEnum(ExceptionCause.EcallFromUMode) => {
            syscallHandler(frame);
            // Skip ecall instruction
            frame.epc += 4;
        },
        else => {
            uart.puts("[trap] Unhandled exception: ");
            uart.putHex(code);
            uart.puts(" at PC: ");
            uart.putHex(frame.epc);
            uart.puts("\n");
            
            // Kill the process
            if (proc.Scheduler.getCurrentProcess()) |p| {
                _ = p;
                proc.Scheduler.exit(-1);
            }
        }
    }
}

// System call handler
fn syscallHandler(frame: *TrapFrame) void {
    const syscall_num = frame.a7;
    
    switch (syscall_num) {
        64 => { // sys_write
            const fd = frame.a0;
            const buf = @as([*]const u8, @ptrFromInt(frame.a1));
            const len = frame.a2;
            frame.a0 = @bitCast(sysWrite(fd, buf, len));
        },
        93 => { // sys_exit  
            const code = @as(i32, @intCast(frame.a0));
            sysExit(code);
            // Never returns
        },
        else => {
            uart.puts("[syscall] Unknown syscall: ");
            uart.putHex(syscall_num);
            uart.puts("\n");
            frame.a0 = @bitCast(@as(isize, -38)); // ENOSYS
        }
    }
}

// System call implementations
fn sysWrite(fd: usize, buf: [*]const u8, len: usize) isize {
    // Validate buffer address (basic check)
    const buf_addr = @intFromPtr(buf);
    if (buf_addr < 0x10000) {
        return -14; // EFAULT
    }
    
    // For now, only support stdout/stderr
    if (fd == 1 or fd == 2) {
        // Direct output to UART
        for (0..len) |i| {
            uart.putc(buf[i]);
        }
        return @intCast(len);
    }
    
    // Try file system
    const result = file.FileTable.sysWrite(@intCast(fd), buf[0..len]);
    if (result >= 0) {
        return result;
    }
    
    return -9; // EBADF
}

fn sysExit(code: i32) noreturn {
    uart.puts("[syscall] Process exiting with code: ");
    uart.putHex(@bitCast(@as(u64, @intCast(code))));
    uart.puts("\n");
    
    proc.Scheduler.exit(code);
    
    // Should not reach here
    while (true) {
        csr.wfi();
    }
}