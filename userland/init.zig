// /init - Minimal system initialization
const syscall = @import("syscall");
const sysno = @import("sysno");

const STDOUT: usize = 1;

fn write_str(str: []const u8) void {
    _ = syscall.syscall3(sysno.sys_write, STDOUT, @intFromPtr(str.ptr), str.len);
}

export fn _start() noreturn {
    // System initialization
    write_str("Welcome to Claudia!\n");
    write_str("Kernel boot complete.\n");
    
    // TODO: Eventually use fork/exec to start shell
    // For now, just print a message and exit
    write_str("Init process complete. Shell would start here.\n");
    
    _ = syscall.syscall3(sysno.sys_exit, 0, 0, 0);
    
    // Never reached
    while (true) {}
}