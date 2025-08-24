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
    // Support both unified build (from root) and standalone kernel build
    const userland_bin_option = b.option([]const u8, "userland-bin-path", "Path to userland binaries") orelse blk: {
        // Try to detect the correct path
        if (std.fs.cwd().access("../zig-out/bin/init", .{})) |_| {
            break :blk "../zig-out/bin";
        } else |_| {}

        if (std.fs.cwd().access("../userland/zig-out/bin/init", .{})) |_| {
            break :blk "../userland/zig-out/bin";
        } else |_| {}

        // Default to the expected path for standalone build
        break :blk "../userland/zig-out/bin";
    };

    const init_asm = b.addWriteFiles();
    const init_asm_content = std.fmt.allocPrint(
        b.allocator,
        \\.section .rodata
        \\.global _user_init_start
        \\.global _user_init_end
        \\_user_init_start:
        \\.incbin "{s}/init"
        \\_user_init_end:
    ,
        .{userland_bin_option},
    ) catch @panic("OOM");
    const init_asm_file = init_asm.add("user_init.S", init_asm_content);

    const shell_asm = b.addWriteFiles();
    const shell_asm_content = std.fmt.allocPrint(
        b.allocator,
        \\.section .rodata
        \\.global _user_shell_start
        \\.global _user_shell_end
        \\_user_shell_start:
        \\.incbin "{s}/shell"
        \\_user_shell_end:
    ,
        .{userland_bin_option},
    ) catch @panic("OOM");
    const shell_asm_file = shell_asm.add("user_shell.S", shell_asm_content);

    kernel.addAssemblyFile(init_asm_file);
    kernel.addAssemblyFile(shell_asm_file);

    kernel.setLinkerScript(b.path("arch/riscv/linker.ld"));
    kernel.linkage = .static;

    // Add ABI directory to module path
    kernel.root_module.addAnonymousImport("abi", .{
        .root_source_file = b.path("../abi/root.zig"),
    });

    // RISC-V specific: use medany code model for position-independent addressing
    kernel.root_module.code_model = .medium;

    const install_kernel = b.addInstallArtifact(kernel, .{});
    b.default_step.dependOn(&install_kernel.step);

    // Add a helpful message step
    const check_userland = b.addSystemCommand(&.{
        "sh", "-c",
        \\if [ ! -f ../userland/zig-out/bin/init ] && [ ! -f ../zig-out/bin/init ]; then
        \\  echo "ERROR: Userland binaries not found!"
        \\  echo "Please build userland first:"
        \\  echo "  cd ../userland && zig build"
        \\  echo "Or use the unified build from the root:"
        \\  echo "  cd .. && zig build"
        \\  exit 1
        \\fi
    });
    kernel.step.dependOn(&check_userland.step);

    // Add clean step
    const clean_step = b.step("clean", "Clean kernel build artifacts");
    const clean_cmd = b.addSystemCommand(&.{
        "rm",      "-rf",
        "zig-out", ".zig-cache",
    });
    clean_step.dependOn(&clean_cmd.step);
}
