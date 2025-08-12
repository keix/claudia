const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .riscv64,
            .os_tag = .freestanding,
            .abi = .none,
        },
    });

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .Debug,
    });

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("init.zig"),
        .target = target,
        .optimize = optimize,
    });

    kernel.addAssemblyFile(b.path("arch/riscv/entry.S"));
    kernel.addAssemblyFile(b.path("arch/riscv/trap.S"));
    kernel.addAssemblyFile(b.path("arch/riscv/umode.S"));
    kernel.addAssemblyFile(b.path("arch/riscv/context.S"));

    // Create assembly wrappers to embed userland binaries
    const init_asm = b.addWriteFiles();
    const init_asm_file = init_asm.add("user_init.S",
        \\.section .rodata
        \\.global _user_init_start
        \\.global _user_init_end
        \\_user_init_start:
        \\.incbin "../userland/zig-out/bin/init"
        \\_user_init_end:
    );
    
    const shell_asm = b.addWriteFiles();
    const shell_asm_file = shell_asm.add("user_shell.S",
        \\.section .rodata
        \\.global _user_shell_start
        \\.global _user_shell_end
        \\_user_shell_start:
        \\.incbin "../userland/zig-out/bin/shell"
        \\_user_shell_end:
    );

    kernel.addAssemblyFile(init_asm_file);
    kernel.addAssemblyFile(shell_asm_file);

    kernel.setLinkerScript(b.path("arch/riscv/linker.ld"));
    kernel.linkage = .static;

    // Add ABI directory to module path
    kernel.root_module.addAnonymousImport("abi", .{
        .root_source_file = b.path("../abi/defs.zig"),
    });
    kernel.root_module.addAnonymousImport("sysno", .{
        .root_source_file = b.path("../abi/sysno.zig"),
    });

    // RISC-V specific: use medany code model for position-independent addressing
    kernel.root_module.code_model = .medium;

    const install_kernel = b.addInstallArtifact(kernel, .{});
    b.default_step.dependOn(&install_kernel.step);
}
