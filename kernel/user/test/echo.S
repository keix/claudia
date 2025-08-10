# Test echo program for Claudia kernel
# This is a minimal user program for testing user mode execution
# It prints "Hello from U-mode!\n" and exits

.section .text
.global _user_echo_start
.global _user_echo_end

_user_echo_start:
    # sys_write(1, message, length)
    li a7, 64           # syscall number for write
    li a0, 1            # file descriptor (stdout)
    la a1, message      # message address
    li a2, 19           # message length
    ecall               # make system call
    
    # sys_exit(0)
    li a7, 93           # syscall number for exit
    li a0, 0            # exit status
    ecall               # make system call
    
    j _user_echo_end    # Jump to end to skip data

.align 4
message:
    .ascii "Hello from U-mode!\n"
    
.align 4    
_user_echo_end: