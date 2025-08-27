const utils = @import("shell/utils");

pub const Command = enum {
    echo,
    help,
    exit,
    ls,
    cat,
    lisp,
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
};
