// Busybox-style multi-command binary
const std = @import("std");
const shell = @import("shell/main");

export fn _start() noreturn {
    // For now, always run as shell
    // TODO: Check argv[0] to determine which command to run
    shell.main();
}
