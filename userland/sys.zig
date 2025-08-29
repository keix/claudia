// Userland syscall wrapper namespace
// Usage: const sys = @import("sys.zig");
//        sys.write(fd, buf, len);
//        sys.exit(code);
//        sys.abi.sysno.sys_write

// Re-export ABI definitions
pub const abi = @import("abi");

// Re-export stat structures
pub const Stat = abi.Stat;

// Re-export syscall wrappers with clean names
pub const write = @import("syscalls/io/write").write;
pub const read = @import("syscalls/io/read").read;
pub const open = @import("syscalls/io/open").open;
pub const close = @import("syscalls/io/close").close;
pub const lseek = @import("syscalls/io/lseek").lseek;
pub const fstat = @import("syscalls/io/fstat").fstat;
pub const getcwd = @import("syscalls/io/getcwd").getcwd;
pub const chdir = @import("syscalls/io/chdir").chdir;
pub const exit = @import("syscalls/proc/exit").exit;
pub const getpid = @import("syscalls/proc/getpid").getpid;

// Directory operations
pub const readdir = @import("syscalls/io/readdir").readdir;
pub const DirEntry = @import("syscalls/io/readdir").DirEntry;

// Time operations
pub const time = @import("syscalls/time/time.zig").time;
pub const clock_gettime = @import("syscalls/time/time.zig").clock_gettime;
pub const nanosleep = @import("syscalls/time/time.zig").nanosleep;
pub const timespec = @import("syscalls/time/time.zig").timespec;

// User/group ID operations
pub const getuid = @import("syscalls/uid/uid.zig").getuid;
pub const geteuid = @import("syscalls/uid/uid.zig").geteuid;
pub const getgid = @import("syscalls/uid/uid.zig").getgid;
pub const getegid = @import("syscalls/uid/uid.zig").getegid;

// Directory operations
pub const mkdirat = @import("syscalls/io/mkdir").mkdirat;
