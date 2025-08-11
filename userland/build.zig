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

    // Optimization options - use ReleaseSmall for minimal binary size
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
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

    // Build /init program
    const init = b.addExecutable(.{
        .name = "init",
        .root_source_file = b.path("init.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
    });

    // Add modules to init
    init.root_module.addImport("syscall", syscall_mod);
    init.root_module.addImport("sysno", sysno_mod);
    init.linkage = .static;

    const install_init = b.addInstallArtifact(init, .{});

    // Default step builds all
    b.default_step.dependOn(&install_echo.step);
    b.default_step.dependOn(&install_init.step);

    // Individual build steps
    const echo_step = b.step("echo", "Build echo command");
    echo_step.dependOn(&install_echo.step);

    const init_step = b.step("init", "Build init program");
    init_step.dependOn(&install_init.step);
}
