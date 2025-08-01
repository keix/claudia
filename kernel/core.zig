const std = @import("std");
const csr = @import("arch/riscv/csr.zig");
const uart = @import("drivers/uart.zig");

pub fn init() noreturn {
    uart.init();
    uart.puts("Hello Claudia!!\n");

    while (true) {
        csr.wfi();
    }
}
