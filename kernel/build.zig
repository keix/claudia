const std = @import("std");

pub fn build(b: *std.Build) void {
    // 標準ターゲットオプション
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .riscv64,
            .os_tag = .freestanding,
            .abi = .none,
        },
    });

    // 標準リリースオプション
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .Debug,
    });

    // カーネル実行ファイルを作成
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("src/kernel.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add assembly boot file
    kernel.addAssemblyFile(b.path("src/boot.S"));

    // フリースタンディング環境のためのリンカオプション
    kernel.setLinkerScript(b.path("linker.ld"));
    kernel.linkage = .static;
    
    // RISC-V specific: use medany code model for position-independent addressing
    kernel.root_module.code_model = .medium;

    // カーネルのインストール
    const install_kernel = b.addInstallArtifact(kernel, .{});
    b.default_step.dependOn(&install_kernel.step);
}
