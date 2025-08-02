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

    kernel.setLinkerScript(b.path("arch/riscv/linker.ld"));
    kernel.linkage = .static;

    // RISC-V specific: use medany code model for position-independent addressing
    kernel.root_module.code_model = .medium;

    const install_kernel = b.addInstallArtifact(kernel, .{});
    b.default_step.dependOn(&install_kernel.step);
}
