// ABI namespace for kernel-userspace interface
// Usage: const abi = @import("abi");
//        abi.sysno.sys_write
//        abi.EFAULT

pub const sysno = @import("sysno.zig");
pub const stat = @import("stat.zig");
pub const consts = @import("consts.zig");

// Re-export all symbols from defs.zig directly
pub usingnamespace @import("defs.zig");

// Re-export stat structures and functions
pub usingnamespace @import("stat.zig");

// Re-export constants
pub usingnamespace @import("consts.zig");

// Add more ABI modules here as needed
// pub const errno = @import("errno.zig");
// pub const signals = @import("signals.zig");
