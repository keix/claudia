// sysno.zig - Linux RISC-V 64-bit syscall numbers
// Reference: https://github.com/torvalds/linux/blob/master/include/uapi/asm-generic/unistd.h
// RISC-V uses the generic syscall numbers

// Process control
pub const sys_fork: usize = 1079;      // Not available, use clone
pub const sys_vfork: usize = 1071;     // Not available, use clone
pub const sys_clone: usize = 220;
pub const sys_execve: usize = 221;
pub const sys_exit: usize = 93;
pub const sys_exit_group: usize = 94;
pub const sys_wait4: usize = 260;
pub const sys_kill: usize = 129;
pub const sys_getpid: usize = 172;
pub const sys_getppid: usize = 173;

// UID/GID
pub const sys_getuid: usize = 174;
pub const sys_geteuid: usize = 175;
pub const sys_getgid: usize = 176;
pub const sys_getegid: usize = 177;
pub const sys_setuid: usize = 146;

// File I/O
pub const sys_read: usize = 63;
pub const sys_write: usize = 64;
pub const sys_openat: usize = 56;      // open is not available, use openat
pub const sys_close: usize = 57;
pub const sys_lseek: usize = 62;
pub const sys_mkdirat: usize = 34;     // mkdir is not available, use mkdirat
pub const sys_unlinkat: usize = 35;    // rmdir/unlink not available, use unlinkat
pub const sys_renameat2: usize = 276;  // rename not available, use renameat2

// Memory
pub const sys_brk: usize = 214;
pub const sys_mmap: usize = 222;
pub const sys_munmap: usize = 215;
pub const sys_mprotect: usize = 226;

// IO control
pub const sys_ioctl: usize = 29;
pub const sys_pselect6: usize = 72;    // select not available, use pselect6
pub const sys_readv: usize = 65;
pub const sys_writev: usize = 66;

// Time
pub const sys_nanosleep: usize = 101;
pub const sys_clock_gettime: usize = 113;
pub const sys_clock_nanosleep: usize = 115;

// Signal
pub const sys_rt_sigaction: usize = 134;
pub const sys_rt_sigprocmask: usize = 135;
pub const sys_rt_sigreturn: usize = 139;

// Socket
pub const sys_socket: usize = 198;
pub const sys_connect: usize = 203;
pub const sys_accept4: usize = 202;    // accept not available, use accept4
pub const sys_bind: usize = 200;
pub const sys_listen: usize = 201;
pub const sys_sendto: usize = 206;
pub const sys_recvfrom: usize = 207;

// Scheduling
pub const sys_sched_yield: usize = 124;

// Additional commonly used syscalls
pub const sys_getcwd: usize = 17;
pub const sys_chdir: usize = 49;
pub const sys_fchdir: usize = 50;
pub const sys_fstat: usize = 80;
pub const sys_fstatat: usize = 79;