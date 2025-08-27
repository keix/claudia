// kernel/syscalls/io.zig - I/O related system calls
const std = @import("std");
const defs = @import("abi");
const file = @import("../file/core.zig");

// sys_lseek implementation
pub fn sys_lseek(fd: usize, offset: usize, whence: usize) isize {
    // Convert whence to u32, validate it
    const whence_u32 = @as(u32, @intCast(whence));
    if (whence_u32 > 2) return defs.EINVAL; // SEEK_SET=0, SEEK_CUR=1, SEEK_END=2

    // Cast offset to signed for proper seeking
    const offset_i64 = @as(i64, @bitCast(offset));

    return file.FileTable.sysLseek(@as(i32, @intCast(fd)), offset_i64, whence_u32);
}
