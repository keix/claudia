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

    // Create shared modules
    const syscall_mod = b.createModule(.{
        .root_source_file = b.path("syscall.zig"),
    });

    const abi_mod = b.createModule(.{
        .root_source_file = b.path("../abi/root.zig"),
    });

    // Build /init program
    const init = b.addExecutable(.{
        .name = "init",
        .root_source_file = b.path("init.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
    });

    // Add modules to init
    init.root_module.addImport("syscall", syscall_mod);
    init.root_module.addImport("abi", abi_mod);
    init.linkage = .static;

    const install_init = b.addInstallArtifact(init, .{});
    b.default_step.dependOn(&install_init.step);

    const init_step = b.step("init", "Build init program");
    init_step.dependOn(&install_init.step);

    // Create sys namespace module
    const sys_mod = b.createModule(.{
        .root_source_file = b.path("sys.zig"),
        .imports = &.{
            .{ .name = "abi", .module = abi_mod },
            .{ .name = "syscalls/io/write", .module = b.createModule(.{
                .root_source_file = b.path("syscalls/io/write.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/io/read", .module = b.createModule(.{
                .root_source_file = b.path("syscalls/io/read.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/io/open", .module = b.createModule(.{
                .root_source_file = b.path("syscalls/io/open.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/proc/exit", .module = b.createModule(.{
                .root_source_file = b.path("syscalls/proc/exit.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
        },
    });

    // Create command modules
    const echo_mod = b.createModule(.{
        .root_source_file = b.path("shell/commands/echo.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
        },
    });

    const help_mod = b.createModule(.{
        .root_source_file = b.path("shell/commands/help.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
        },
    });

    const exit_mod = b.createModule(.{
        .root_source_file = b.path("shell/commands/exit.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
        },
    });

    // Create commands index module
    const commands_index_mod = b.createModule(.{
        .root_source_file = b.path("shell/commands/index.zig"),
        .imports = &.{
            .{ .name = "echo.zig", .module = echo_mod },
            .{ .name = "help.zig", .module = help_mod },
            .{ .name = "exit.zig", .module = exit_mod },
        },
    });

    // Create shell module
    const shell_main_mod = b.createModule(.{
        .root_source_file = b.path("shell/main.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/commands/index", .module = commands_index_mod },
        },
    });

    // Build shell program (busybox-style)
    const shell = b.addExecutable(.{
        .name = "shell",
        .root_source_file = b.path("bin/shell.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
    });

    // Add modules to shell
    shell.root_module.addImport("syscall", syscall_mod);
    shell.root_module.addImport("abi", abi_mod);
    shell.root_module.addImport("shell/main", shell_main_mod);
    shell.linkage = .static;

    const install_shell = b.addInstallArtifact(shell, .{});
    b.default_step.dependOn(&install_shell.step);

    const shell_step = b.step("shell", "Build shell program");
    shell_step.dependOn(&install_shell.step);
}
