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
pub const close = @import("syscalls/io/close").close;
pub const lseek = @import("syscalls/io/lseek").lseek;
pub const exit = @import("syscalls/proc/exit").exit;
pub const getpid = @import("syscalls/proc/getpid").getpid;

// Directory operations
pub const readdir = @import("syscalls/io/readdir").readdir;
pub const DirEntry = @import("syscalls/io/readdir").DirEntry;
