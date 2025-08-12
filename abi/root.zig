// ABI namespace for kernel-userspace interface
// Usage: const abi = @import("abi");
//        abi.sysno.sys_write
//        abi.types.pid_t

pub const sysno = @import("sysno.zig");
pub const types = @import("defs.zig");

// Add more ABI modules here as needed
// pub const errno = @import("errno.zig");
// pub const signals = @import("signals.zig");
