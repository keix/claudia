const utils = @import("shell/utils");

pub const Command = enum {
    echo,
    help,
    exit,
};

pub const CommandEntry = struct {
    name: []const u8,
    func: *const fn (*const utils.Args) void,
};

pub const commands = [_]CommandEntry{
    .{ .name = "echo", .func = @import("echo.zig").main },
    .{ .name = "help", .func = @import("help.zig").main },
    .{ .name = "exit", .func = @import("exit.zig").main },
};
