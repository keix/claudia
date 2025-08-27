// Provides low-level system call wrappers for Claudia (RISC-V 64-bit)
// Each function corresponds to a syscall with N arguments (0 to 6)
// RISC-V Linux ABI:
// - System call number in a7
// - Arguments in a0-a5
// - Return value in a0
// - ecall instruction triggers the system call

pub fn syscall0(number: usize) isize {
    var result: isize = undefined;
    asm volatile (
        \\ ecall
        : [ret] "={a0}" (result),
        : [num] "{a7}" (number),
        : "memory"
    );
    return result;
}

pub fn syscall1(number: usize, arg1: usize) isize {
    var result: isize = undefined;
    asm volatile (
        \\ ecall
        : [ret] "={a0}" (result),
        : [num] "{a7}" (number),
          [a1] "{a0}" (arg1),
        : "memory"
    );
    return result;
}

pub fn syscall2(number: usize, arg1: usize, arg2: usize) isize {
    var result: isize = undefined;
    asm volatile (
        \\ ecall
        : [ret] "={a0}" (result),
        : [num] "{a7}" (number),
          [a1] "{a0}" (arg1),
          [a2] "{a1}" (arg2),
        : "memory"
    );
    return result;
}

pub fn syscall3(number: usize, arg1: usize, arg2: usize, arg3: usize) isize {
    var result: isize = undefined;
    asm volatile (
        \\ ecall
        : [ret] "={a0}" (result),
        : [num] "{a7}" (number),
          [a1] "{a0}" (arg1),
          [a2] "{a1}" (arg2),
          [a3] "{a2}" (arg3),
        : "memory"
    );
    return result;
}

pub fn syscall4(number: usize, arg1: usize, arg2: usize, arg3: usize, arg4: usize) isize {
    var result: isize = undefined;
    asm volatile (
        \\ ecall
        : [ret] "={a0}" (result),
        : [num] "{a7}" (number),
          [a1] "{a0}" (arg1),
          [a2] "{a1}" (arg2),
          [a3] "{a2}" (arg3),
          [a4] "{a3}" (arg4),
        : "memory"
    );
    return result;
}

pub fn syscall5(number: usize, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize) isize {
    var result: isize = undefined;
    asm volatile (
        \\ ecall
        : [ret] "={a0}" (result),
        : [num] "{a7}" (number),
          [a1] "{a0}" (arg1),
          [a2] "{a1}" (arg2),
          [a3] "{a2}" (arg3),
          [a4] "{a3}" (arg4),
          [a5] "{a4}" (arg5),
        : "memory"
    );
    return result;
}

pub fn syscall6(number: usize, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize, arg6: usize) isize {
    var result: isize = undefined;
    asm volatile (
        \\ ecall
        : [ret] "={a0}" (result),
        : [num] "{a7}" (number),
          [a1] "{a0}" (arg1),
          [a2] "{a1}" (arg2),
          [a3] "{a2}" (arg3),
          [a4] "{a3}" (arg4),
          [a5] "{a4}" (arg5),
          [a6] "{a5}" (arg6),
        : "memory"
    );
    return result;
}
