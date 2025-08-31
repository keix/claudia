const utils = @import("shell/utils");

pub const Command = enum {
    echo,
    help,
    exit,
    ls,
    cat,
    lisp,
    date,
    touch,
    id,
    mkdir,
};

pub const CommandEntry = struct {
    name: []const u8,
    func: *const fn (*const utils.Args) void,
};

pub const commands = [_]CommandEntry{
    .{ .name = "echo", .func = @import("echo.zig").main },
    .{ .name = "help", .func = @import("help.zig").main },
    .{ .name = "exit", .func = @import("exit.zig").main },
    .{ .name = "ls", .func = @import("ls.zig").main },
    .{ .name = "cat", .func = @import("cat.zig").main },
    .{ .name = "lisp", .func = @import("lisp.zig").main },
    .{ .name = "pid", .func = @import("pid.zig").main },
    .{ .name = "seek", .func = @import("seek.zig").main },
    .{ .name = "pwd", .func = @import("pwd.zig").main },
    .{ .name = "cd", .func = @import("cd.zig").main },
    .{ .name = "fstat", .func = @import("fstat.zig").main },
    .{ .name = "date", .func = @import("date.zig").main },
    .{ .name = "touch", .func = @import("touch.zig").main },
    .{ .name = "id", .func = @import("id.zig").main },
    .{ .name = "mkdir", .func = @import("mkdir.zig").main },
    .{ .name = "rm", .func = @import("rm.zig").main },
    .{ .name = "fork_test", .func = @import("fork_test.zig").main },
    .{ .name = "fork_demo", .func = @import("fork_demo.zig").main },
};
