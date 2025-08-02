# Claudia ABI Definitions

This directory contains shared Application Binary Interface (ABI) definitions used by both the kernel and userland components.

## Files

- `sysno.zig` - System call numbers (Linux RISC-V 64-bit compatible)
- `defs.zig` - POSIX-style constants and flags

## Usage

### In Kernel
```zig
const abi = @import("../abi/sysno.zig");
// Handle syscall number abi.sys_write
```

### In Userland
```zig
const abi = @import("../abi/sysno.zig");
// Make syscall with number abi.sys_write
```

## Note

`syscall.zig` remains userland-specific as it contains `ecall` instructions for making system calls from user space. The kernel side handles syscall reception, not invocation.