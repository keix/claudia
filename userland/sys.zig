// Userland syscall wrapper namespace
// Usage: const sys = @import("sys.zig");
//        sys.write(fd, buf, len);
//        sys.exit(code);
//        sys.abi.sysno.sys_write

// Re-export ABI definitions
pub const abi = @import("abi");

// Re-export syscall wrappers with clean names
pub const write = @import("syscalls/io/write").write;
pub const read = @import("syscalls/io/read").read;
pub const open = @import("syscalls/io/open").open;
pub const exit = @import("syscalls/proc/exit").exit;
