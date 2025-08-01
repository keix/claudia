const syscall = @import("syscall");
const sysno = @import("sysno");

/// Terminates the calling process with the given exit code using the raw `exit` syscall.
///
/// - `code`: the exit code to return to the OS
///
/// This function does not return.
pub fn exit(code: u8) noreturn {
    _ = syscall.syscall1(sysno.sys_exit, code);
    unreachable;
}
