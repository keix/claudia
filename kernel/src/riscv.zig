// RISC-V architecture definitions and utilities
// Based on RISC-V privileged spec v1.11

const std = @import("std");

// RISC-V hart (hardware thread) local storage
pub const HartLocal = struct {
    id: u64,
    stack: [*]u8,
    scratch: [5]u64,
};

// CSR (Control and Status Register) numbers
pub const CSR = struct {
    // Machine-level CSRs
    pub const mstatus: u64 = 0x300;
    pub const misa: u64 = 0x301;
    pub const medeleg: u64 = 0x302;
    pub const mideleg: u64 = 0x303;
    pub const mie: u64 = 0x304;
    pub const mtvec: u64 = 0x305;
    pub const mcounteren: u64 = 0x306;
    pub const mscratch: u64 = 0x340;
    pub const mepc: u64 = 0x341;
    pub const mcause: u64 = 0x342;
    pub const mtval: u64 = 0x343;
    pub const mip: u64 = 0x344;

    // Supervisor-level CSRs
    pub const sstatus: u64 = 0x100;
    pub const sie: u64 = 0x104;
    pub const stvec: u64 = 0x105;
    pub const scounteren: u64 = 0x106;
    pub const sscratch: u64 = 0x140;
    pub const sepc: u64 = 0x141;
    pub const scause: u64 = 0x142;
    pub const stval: u64 = 0x143;
    pub const sip: u64 = 0x144;
    pub const satp: u64 = 0x180;
};

// mstatus register bits
pub const MSTATUS = struct {
    pub const MPP_MASK: u64 = 3 << 11;
    pub const MPP_M: u64 = 3 << 11;
    pub const MPP_S: u64 = 1 << 11;
    pub const MPP_U: u64 = 0 << 11;
    pub const MIE: u64 = 1 << 3;
    pub const MPIE: u64 = 1 << 7;
    pub const SPP: u64 = 1 << 8;
    pub const SPIE: u64 = 1 << 5;
    pub const SIE: u64 = 1 << 1;
};

// CSR read operation
pub inline fn readCsr(comptime csr: u64) u64 {
    return asm volatile ("csrr %[ret], %[csr]"
        : [ret] "=r" (-> u64),
        : [csr] "i" (csr),
    );
}

// CSR write operation
pub inline fn writeCsr(comptime csr: u64, value: u64) void {
    asm volatile ("csrw %[csr], %[value]"
        :
        : [csr] "i" (csr),
          [value] "r" (value),
    );
}

// CSR set bits operation
pub inline fn setCsr(comptime csr: u64, value: u64) void {
    asm volatile ("csrs %[csr], %[value]"
        :
        : [csr] "i" (csr),
          [value] "r" (value),
    );
}

// CSR clear bits operation
pub inline fn clearCsr(comptime csr: u64, value: u64) void {
    asm volatile ("csrc %[csr], %[value]"
        :
        : [csr] "i" (csr),
          [value] "r" (value),
    );
}

// Read mstatus
pub inline fn readMstatus() u64 {
    return readCsr(CSR.mstatus);
}

// Write mstatus
pub inline fn writeMstatus(value: u64) void {
    writeCsr(CSR.mstatus, value);
}

// Read mepc
pub inline fn readMepc() u64 {
    return readCsr(CSR.mepc);
}

// Write mepc
pub inline fn writeMepc(value: u64) void {
    writeCsr(CSR.mepc, value);
}

// Read satp
pub inline fn readSatp() u64 {
    return readCsr(CSR.satp);
}

// Write satp
pub inline fn writeSatp(value: u64) void {
    writeCsr(CSR.satp, value);
}

// Memory barriers
pub inline fn sfenceVma() void {
    asm volatile ("sfence.vma zero, zero" ::: "memory");
}

pub inline fn fence() void {
    asm volatile ("fence" ::: "memory");
}

pub inline fn fenceI() void {
    asm volatile ("fence.i" ::: "memory");
}

// Wait for interrupt
pub inline fn wfi() void {
    asm volatile ("wfi");
}

// Supervisor return
pub inline fn sret() void {
    asm volatile ("sret");
}

// Machine return
pub inline fn mret() void {
    asm volatile ("mret");
}

// Make SBI (Supervisor Binary Interface) call
pub fn sbiCall(eid: u64, fid: u64, arg0: u64, arg1: u64, arg2: u64) u64 {
    return asm volatile (
        \\ecall
        : [ret] "={x10}" (-> u64),
        : [eid] "{x17}" (eid),
          [fid] "{x16}" (fid),
          [a0] "{x10}" (arg0),
          [a1] "{x11}" (arg1),
          [a2] "{x12}" (arg2),
        : "memory"
    );
}

// SBI console putchar
pub fn sbiConsolePutchar(c: u8) void {
    _ = sbiCall(0x01, 0, c, 0, 0);
}

// Read time register
pub inline fn readTime() u64 {
    return asm volatile ("rdtime %[ret]"
        : [ret] "=r" (-> u64),
    );
}

// Read cycle counter
pub inline fn readCycle() u64 {
    return asm volatile ("rdcycle %[ret]"
        : [ret] "=r" (-> u64),
    );
}

// Hardware thread ID
pub inline fn readMhartid() u64 {
    return readCsr(0xF14);
}

// Read stack pointer
pub inline fn readSp() u64 {
    return asm volatile ("mv %[ret], sp"
        : [ret] "=r" (-> u64),
    );
}

// Read thread pointer
pub inline fn readTp() u64 {
    return asm volatile ("mv %[ret], tp"
        : [ret] "=r" (-> u64),
    );
}

// Write thread pointer
pub inline fn writeTp(value: u64) void {
    asm volatile ("mv tp, %[value]"
        :
        : [value] "r" (value),
    );
}

// RISC-V exception codes
pub const Exception = struct {
    pub const InstructionAddressMisaligned: u64 = 0;
    pub const InstructionAccessFault: u64 = 1;
    pub const IllegalInstruction: u64 = 2;
    pub const Breakpoint: u64 = 3;
    pub const LoadAddressMisaligned: u64 = 4;
    pub const LoadAccessFault: u64 = 5;
    pub const StoreAddressMisaligned: u64 = 6;
    pub const StoreAccessFault: u64 = 7;
    pub const UserEcall: u64 = 8;
    pub const SupervisorEcall: u64 = 9;
    pub const MachineEcall: u64 = 11;
    pub const InstructionPageFault: u64 = 12;
    pub const LoadPageFault: u64 = 13;
    pub const StorePageFault: u64 = 15;
};

// RISC-V interrupt codes
pub const Interrupt = struct {
    pub const SupervisorSoftware: u64 = 1;
    pub const MachineSoftware: u64 = 3;
    pub const SupervisorTimer: u64 = 5;
    pub const MachineTimer: u64 = 7;
    pub const SupervisorExternal: u64 = 9;
    pub const MachineExternal: u64 = 11;
};

// Page table entry bits
pub const PTE = struct {
    pub const V: u64 = 1 << 0; // Valid
    pub const R: u64 = 1 << 1; // Read
    pub const W: u64 = 1 << 2; // Write
    pub const X: u64 = 1 << 3; // Execute
    pub const U: u64 = 1 << 4; // User
    pub const G: u64 = 1 << 5; // Global
    pub const A: u64 = 1 << 6; // Accessed
    pub const D: u64 = 1 << 7; // Dirty
};

// SATP mode for Sv39
pub const SATP_SV39: u64 = 8 << 60;

// Make SATP value
pub inline fn makeSatp(mode: u64, ppn: u64) u64 {
    return mode | ppn;
}

// Physical memory layout (for QEMU virt machine)
pub const UART0: u64 = 0x10000000;
pub const UART0_IRQ: u32 = 10;

// Power off the machine (QEMU test device)
pub fn poweroff() noreturn {
    const VIRT_TEST = 0x100000;
    const addr = @intToPtr(*volatile u32, VIRT_TEST);
    addr.* = 0x5555; // Magic value for poweroff
    while (true) {
        wfi();
    }
}