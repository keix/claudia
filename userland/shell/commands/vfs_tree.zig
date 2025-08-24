// vfs_tree - Debug command to print VFS tree
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    // This is a debug command that triggers VFS tree printing in kernel
    // We'll use a special path that the kernel recognizes
    const fd = sys.open(@ptrCast("/__vfs_debug_tree__"), 0, 0);
    if (fd < 0) {
        utils.writeStr("VFS debug not available\n");
    }
}
