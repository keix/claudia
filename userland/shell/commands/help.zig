// Help command implementation
const sys = @import("sys");
const utils = @import("shell/utils");

const STDOUT: usize = 1;

fn write_str(str: []const u8) void {
    _ = sys.write(STDOUT, @ptrCast(str.ptr), str.len);
}

pub fn main(args: *const utils.Args) void {
    _ = args;

    write_str("Available commands:\n");
    write_str("  echo      - Echo arguments to stdout\n");
    write_str("  help      - Show this help\n");
    write_str("  exit      - Exit the shell\n");
    write_str("  ls        - List directory contents\n");
    write_str("  cat       - Display file contents\n");
    write_str("  lisp      - Minimal Lisp REPL\n");
    write_str("  test_open - Test the open system call\n");
    write_str("  test_vfs  - Test VFS path resolution\n");
    write_str("  test_ramdisk - Test RAM disk\n");
    write_str("  test_simplefs - Test SimpleFS\n");
    write_str("  init_fs   - Format SimpleFS on RAM disk\n");
    write_str("  write_fs  - Write a file to SimpleFS\n");
    write_str("  read_fs   - Read a file from SimpleFS\n");
    write_str("  list_fs   - List files in SimpleFS\n");
}
