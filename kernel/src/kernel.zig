const std = @import("std");

export fn kernel_main() noreturn {
    // Simple test: write to UART
    const uart_addr = @as(*volatile u8, @ptrFromInt(0x10000000));

    const msg = "Hello from RISC-V kernel!\n";
    for (msg) |char| {
        uart_addr.* = char;
    }

    // Hang
    while (true) {
        asm volatile ("wfi");
    }
}
