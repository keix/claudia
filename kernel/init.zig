// Kernel initialization entry point
// This is the first Zig code executed after boot

const std = @import("std");
const core = @import("core.zig");

// Entry point called from assembly boot code
export fn start() noreturn {
    // Initialize kernel subsystems and start main kernel
    core.init();
    unreachable; // Should never return
}
