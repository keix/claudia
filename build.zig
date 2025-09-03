const std = @import("std");

pub fn build(b: *std.Build) void {
    // Add clean step first to avoid unnecessary dependencies
    const clean_step = b.step("clean", "Clean build artifacts");
    const clean_cmd = b.addSystemCommand(&.{
        "rm",                  "-rf",
        "zig-out",             ".zig-cache",
        "kernel/.zig-cache",   "kernel/zig-out",
        "userland/.zig-cache", "userland/zig-out",
    });
    clean_step.dependOn(&clean_cmd.step);

    // Target options for RISC-V 64-bit freestanding
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .riscv64,
            .os_tag = .freestanding,
            .abi = .none,
        },
    });

    // Optimization options
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    // First, create ABI module that both kernel and userland will use
    const abi_mod = b.createModule(.{
        .root_source_file = b.path("abi/root.zig"),
    });

    // ======================
    // Build Userland First
    // ======================

    // Create shared modules for userland
    const syscall_mod = b.createModule(.{
        .root_source_file = b.path("userland/syscall.zig"),
    });

    // Build init program
    const init = b.addExecutable(.{
        .name = "init",
        .root_source_file = b.path("userland/sbin/init.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
    });
    init.root_module.addImport("syscall", syscall_mod);
    init.root_module.addImport("abi", abi_mod);
    init.linkage = .static;

    const install_init = b.addInstallArtifact(init, .{});

    // Build shell program
    const shell = b.addExecutable(.{
        .name = "shell",
        .root_source_file = b.path("userland/bin/shell.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
    });

    // Create sys module for shell
    const sys_mod = b.createModule(.{
        .root_source_file = b.path("userland/sys.zig"),
        .imports = &.{
            .{ .name = "abi", .module = abi_mod },
            .{ .name = "syscalls/io/write", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/io/write.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/io/read", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/io/read.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/io/open", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/io/open.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/io/close", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/io/close.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/io/lseek", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/io/lseek.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/io/fstat", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/io/fstat.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/io/stat", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/io/stat.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/io/dup", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/io/dup.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/io/getcwd", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/io/getcwd.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/io/chdir", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/io/chdir.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/io/readdir", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/io/readdir.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/proc/exit", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/proc/exit.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/proc/getpid", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/proc/getpid.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/proc/getppid", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/proc/getppid.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/time/time.zig", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/time/time.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/uid/uid.zig", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/uid/uid.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/io/mkdir", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/io/mkdir.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/io/unlinkat", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/io/unlinkat.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/proc/fork", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/proc/fork.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/proc/yield", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/proc/yield.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/proc/wait", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/proc/wait.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
            .{ .name = "syscalls/mem/brk", .module = b.createModule(.{
                .root_source_file = b.path("userland/syscalls/mem/brk.zig"),
                .imports = &.{
                    .{ .name = "syscall", .module = syscall_mod },
                    .{ .name = "abi", .module = abi_mod },
                },
            }) },
        },
    });

    // Create shell utils module
    const shell_utils_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/utils.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
        },
    });

    // Create command modules
    const echo_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/echo.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const help_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/help.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const exit_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/exit.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const ls_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/ls.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
            .{ .name = "abi", .module = abi_mod },
            .{ .name = "syscall", .module = syscall_mod },
        },
    });

    const cat_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/cat.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const lisp_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/lisp.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const pid_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/pid.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const ppid_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/ppid.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const seek_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/seek.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const pwd_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/pwd.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const cd_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/cd.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const fstat_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/fstat.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const date_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/date.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const touch_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/touch.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const id_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/id.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const mkdir_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/mkdir.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
            .{ .name = "abi", .module = abi_mod },
        },
    });

    const rm_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/rm.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const sleep_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/sleep.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    const brktest_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/brktest.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    // Create commands index module
    const commands_index_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/commands/index.zig"),
        .imports = &.{
            .{ .name = "echo.zig", .module = echo_mod },
            .{ .name = "help.zig", .module = help_mod },
            .{ .name = "exit.zig", .module = exit_mod },
            .{ .name = "ls.zig", .module = ls_mod },
            .{ .name = "cat.zig", .module = cat_mod },
            .{ .name = "lisp.zig", .module = lisp_mod },
            .{ .name = "pid.zig", .module = pid_mod },
            .{ .name = "ppid.zig", .module = ppid_mod },
            .{ .name = "seek.zig", .module = seek_mod },
            .{ .name = "pwd.zig", .module = pwd_mod },
            .{ .name = "cd.zig", .module = cd_mod },
            .{ .name = "fstat.zig", .module = fstat_mod },
            .{ .name = "date.zig", .module = date_mod },
            .{ .name = "touch.zig", .module = touch_mod },
            .{ .name = "id.zig", .module = id_mod },
            .{ .name = "mkdir.zig", .module = mkdir_mod },
            .{ .name = "rm.zig", .module = rm_mod },
            .{ .name = "sleep.zig", .module = sleep_mod },
            .{ .name = "brktest.zig", .module = brktest_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    // Create shell module
    const shell_main_mod = b.createModule(.{
        .root_source_file = b.path("userland/shell/main.zig"),
        .imports = &.{
            .{ .name = "sys", .module = sys_mod },
            .{ .name = "shell/commands/index", .module = commands_index_mod },
            .{ .name = "shell/utils", .module = shell_utils_mod },
        },
    });

    shell.root_module.addImport("syscall", syscall_mod);
    shell.root_module.addImport("abi", abi_mod);
    shell.root_module.addImport("shell/main", shell_main_mod);
    shell.linkage = .static;

    const install_shell = b.addInstallArtifact(shell, .{});

    // ======================
    // Build Kernel
    // ======================

    // Build kernel (depends on userland being built first)
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("kernel/init.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add kernel dependencies
    kernel.addAssemblyFile(b.path("kernel/arch/riscv/entry.S"));
    kernel.addAssemblyFile(b.path("kernel/arch/riscv/context.S"));
    kernel.addAssemblyFile(b.path("kernel/arch/riscv/trap.S"));
    kernel.addAssemblyFile(b.path("kernel/arch/riscv/umode.S"));
    kernel.addAssemblyFile(b.path("kernel/arch/riscv/child_return.S"));

    // Create assembly wrappers to embed userland binaries
    const init_asm = b.addWriteFiles();
    const init_asm_file = init_asm.add("user_init.S",
        \\.section .rodata
        \\.global _user_init_start
        \\.global _user_init_end
        \\_user_init_start:
        \\.incbin "zig-out/bin/init"
        \\_user_init_end:
    );
    init_asm.step.dependOn(&install_init.step);

    const shell_asm = b.addWriteFiles();
    const shell_asm_file = shell_asm.add("user_shell.S",
        \\.section .rodata
        \\.global _user_shell_start
        \\.global _user_shell_end
        \\_user_shell_start:
        \\.incbin "zig-out/bin/shell"
        \\_user_shell_end:
    );
    shell_asm.step.dependOn(&install_shell.step);

    kernel.addAssemblyFile(init_asm_file);
    kernel.addAssemblyFile(shell_asm_file);
    kernel.setLinkerScript(b.path("kernel/arch/riscv/linker.ld"));
    kernel.root_module.addImport("abi", abi_mod);
    kernel.linkage = .static;

    // RISC-V specific: use medany code model
    kernel.root_module.code_model = .medium;

    // Disable GP relaxation to prevent GP-relative addressing issues
    kernel.root_module.addCMacro("__riscv_no_relax", "1");

    const install_kernel = b.addInstallArtifact(kernel, .{});

    // Kernel depends on userland being built first
    install_kernel.step.dependOn(&install_init.step);
    install_kernel.step.dependOn(&install_shell.step);

    // ======================
    // Build Steps
    // ======================

    // Build mkinitrd tool (for host system)
    const mkinitrd = b.addExecutable(.{
        .name = "mkinitrd",
        .root_source_file = b.path("mkinitrd.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });
    const install_mkinitrd = b.addInstallArtifact(mkinitrd, .{});

    // Create initrd with sample files
    const initrd_step = b.step("initrd", "Create initrd image");
    initrd_step.dependOn(&install_mkinitrd.step);

    // Create initrd from rootfs directory
    const create_initrd_cmd = b.addSystemCommand(&.{
        "zig-out/bin/mkinitrd", "zig-out/initrd.img", "rootfs",
    });
    create_initrd_cmd.step.dependOn(&install_mkinitrd.step);
    initrd_step.dependOn(&create_initrd_cmd.step);

    // Create assembly wrapper to embed initrd
    const initrd_asm = b.addWriteFiles();
    const initrd_asm_file = initrd_asm.add("initrd_data.S",
        \\.section .rodata
        \\.global _initrd_start
        \\.global _initrd_end
        \\_initrd_start:
        \\.incbin "zig-out/initrd.img"
        \\_initrd_end:
    );
    initrd_asm.step.dependOn(&create_initrd_cmd.step);

    // Add the embedded initrd to kernel
    kernel.addAssemblyFile(initrd_asm_file);

    // Default build depends on kernel (which depends on userland)
    b.default_step.dependOn(&install_kernel.step);
    b.default_step.dependOn(initrd_step);

    // Add individual build steps
    const kernel_step = b.step("kernel", "Build only the kernel");
    kernel_step.dependOn(&install_kernel.step);

    const userland_step = b.step("userland", "Build only userland programs");
    userland_step.dependOn(&install_init.step);
    userland_step.dependOn(&install_shell.step);

    // Add run step for QEMU (with embedded initrd)
    const run_step = b.step("run", "Run in QEMU");
    const run_cmd = b.addSystemCommand(&.{
        "qemu-system-riscv64",
        "-M",
        "virt",
        "-m",
        "256M",
        "-nographic",
        "-kernel",
        "zig-out/bin/kernel",
    });
    run_cmd.step.dependOn(b.default_step);
    run_step.dependOn(&run_cmd.step);
}
