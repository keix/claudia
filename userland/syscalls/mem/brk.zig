// userland/syscalls/mem/brk.zig - Program break (heap) management
const syscall = @import("syscall");
const abi = @import("abi");

// sbrk - Increment program break by increment bytes
// Returns previous program break on success, @intFromError(error) on failure
pub fn sbrk(increment: isize) isize {
    // Get current break (brk(0) returns current break)
    const current = syscall.syscall1(abi.sysno.sys_brk, 0);

    if (increment == 0) {
        return current;
    }

    // Calculate new break
    const new_break = @as(usize, @intCast(current + increment));

    // Try to set new break
    const result = syscall.syscall1(abi.sysno.sys_brk, new_break);

    // Check if brk succeeded (new break equals requested break)
    if (result == @as(isize, @intCast(new_break))) {
        return current; // Return old break
    }

    // Failed to extend heap
    return -abi.ENOMEM;
}

// brk - Set program break to addr
// Returns 0 on success, -1 on failure
pub fn brk(addr: usize) isize {
    const result = syscall.syscall1(abi.sysno.sys_brk, addr);

    // Check if brk succeeded
    if (result == @as(isize, @intCast(addr))) {
        return 0;
    }

    return -1;
}
