const utils = @import("shell/utils");

pub const Command = enum {
    echo,
    help,
    exit,
    ls,
    cat,
    test_open,
    test_vfs,
    test_file,
    test_null,
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
    .{ .name = "test_open", .func = @import("test_open.zig").main },
    .{ .name = "test_vfs", .func = @import("test_vfs.zig").main },
    .{ .name = "test_file", .func = @import("test_file.zig").main },
    .{ .name = "test_null", .func = @import("test_null.zig").main },
};
