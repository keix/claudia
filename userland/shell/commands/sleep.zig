// sleep command - delay for a specified amount of time
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    if (args.argc < 2) {
        utils.writeStr("Usage: sleep seconds\n");
        return;
    }

    // Parse seconds
    const seconds_str = args.argv[1];
    var seconds: u64 = 0;
    var i: usize = 0;

    // Simple integer parsing
    while (i < seconds_str.len) : (i += 1) {
        const c = seconds_str[i];
        if (c < '0' or c > '9') {
            utils.writeStr("sleep: invalid time interval '");
            utils.writeStr(seconds_str);
            utils.writeStr("'\n");
            return;
        }
        seconds = seconds * 10 + (c - '0');
    }

    // Prepare timespec structure
    var req = sys.timespec{
        .tv_sec = @intCast(seconds),
        .tv_nsec = 0,
    };

    // Call nanosleep
    const result = sys.nanosleep(&req, null);

    if (result < 0) {
        utils.writeStr("sleep: sleep was interrupted\n");
    }
}
