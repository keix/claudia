const std = @import("std");

pub fn build(b: *std.Build) void {
    // Target options for RISC-V 64-bit freestanding (for custom kernel)
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .riscv64,
            .os_tag = .freestanding,
            .abi = .none,
        },
    });

    // Optimization options - use Debug to make troubleshooting easier
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .Debug,
    });

    // Create shared modules
    const syscall_mod = b.createModule(.{
        .root_source_file = b.path("syscall.zig"),
    });
    const sysno_mod = b.createModule(.{
        .root_source_file = b.path("../abi/sysno.zig"),
    });
    const write_mod = b.createModule(.{
        .root_source_file = b.path("syscalls/io/write.zig"),
        .imports = &.{
            .{ .name = "syscall", .module = syscall_mod },
            .{ .name = "sysno", .module = sysno_mod },
        },
    });
    const exit_mod = b.createModule(.{
        .root_source_file = b.path("syscalls/proc/exit.zig"),
        .imports = &.{
            .{ .name = "syscall", .module = syscall_mod },
            .{ .name = "sysno", .module = sysno_mod },
        },
    });

    // Build echo command
    const echo = b.addExecutable(.{
        .name = "echo",
        .root_source_file = b.path("coreutils/echo.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add modules to echo
    echo.root_module.addImport("syscalls/io/write", write_mod);
    echo.root_module.addImport("syscalls/proc/exit", exit_mod);
    echo.linkage = .static;

    const install_echo = b.addInstallArtifact(echo, .{});

    // Default step builds echo
    b.default_step.dependOn(&install_echo.step);

    // Individual build step for echo
    const echo_step = b.step("echo", "Build echo command");
    echo_step.dependOn(&install_echo.step);
}
