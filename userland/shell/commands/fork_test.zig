// Fork test command - demonstrates process forking and scheduling
const sys = @import("sys");
const utils = @import("shell/utils");

fn writeDec(value: u32) void {
    var buf: [20]u8 = undefined;
    var pos: usize = buf.len;
    var val = value;
    
    if (val == 0) {
        utils.writeStr("0");
        return;
    }
    
    while (val > 0 and pos > 0) {
        pos -= 1;
        buf[pos] = @as(u8, '0' + @as(u8, @intCast(val % 10)));
        val /= 10;
    }
    
    utils.writeStr(buf[pos..]);
}

pub fn main(args: *const utils.Args) void {
    _ = args;
    
    const parent_pid = sys.getpid();
    utils.writeStr("Parent process PID: ");
    writeDec(@as(u32, @intCast(parent_pid)));
    utils.writeStr("\n");
    
    // Fork a child process
    const pid = sys.fork() catch {
        utils.writeStr("Fork failed!\n");
        return;
    };
    
    if (pid == 0) {
        // Child process
        const child_pid = sys.getpid();
        utils.writeStr("Child process started, PID: ");
        writeDec(@as(u32, @intCast(child_pid)));
        utils.writeStr("\n");
        
        // Child does some work
        var count: u32 = 0;
        while (count < 5) {
            utils.writeStr("  [Child] Working... ");
            writeDec(count);
            utils.writeStr("\n");
            
            // Sleep for 500ms
            const ts = sys.timespec{
                .tv_sec = 0,
                .tv_nsec = 500_000_000,
            };
            _ = sys.nanosleep(&ts, null);
            
            count += 1;
        }
        
        utils.writeStr("Child process exiting\n");
        sys.exit(0);
    } else {
        // Parent process
        utils.writeStr("Parent: Child created with PID ");
        writeDec(@as(u32, @intCast(pid)));
        utils.writeStr("\n");
        utils.writeStr("Parent: Returning to shell (child continues in background)\n");
        // Parent returns immediately to shell
    }
}