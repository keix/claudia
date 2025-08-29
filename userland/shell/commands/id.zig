// id command - print user and group IDs
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    // Get user and group IDs
    const uid = sys.getuid();
    const gid = sys.getgid();
    const euid = sys.geteuid();
    const egid = sys.getegid();

    // Print IDs
    utils.writeStr("uid=");
    printNum(uid);
    utils.writeStr("(root) gid=");
    printNum(gid);
    utils.writeStr("(root)");

    // Print effective IDs if different
    if (uid != euid or gid != egid) {
        utils.writeStr(" euid=");
        printNum(euid);
        utils.writeStr(" egid=");
        printNum(egid);
    }

    utils.writeStr("\n");
}

fn printNum(n: i32) void {
    if (n == 0) {
        utils.writeStr("0");
        return;
    }

    var buf: [32]u8 = undefined;
    var i: usize = 0;
    var num = n;

    // Handle negative numbers
    const negative = n < 0;
    if (negative) {
        num = -num;
    }

    // Convert to string (reverse order)
    while (num > 0) : (i += 1) {
        buf[i] = '0' + @as(u8, @intCast(@mod(num, 10)));
        num = @divTrunc(num, 10);
    }

    // Print sign if negative
    if (negative) {
        utils.writeStr("-");
    }

    // Print digits in correct order
    while (i > 0) {
        i -= 1;
        const s = [_]u8{buf[i]};
        utils.writeStr(&s);
    }
}
