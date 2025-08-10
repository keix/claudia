# User mode transition for RISC-V
# Provides one-way transition from S-mode to U-mode

.section .text
.global switch_to_user_mode
.align 4

# switch_to_user_mode(entry_point, user_stack, kernel_stack)
# a0 = user entry point (sepc)
# a1 = user stack pointer  
# a2 = kernel stack pointer (for sscratch)
switch_to_user_mode:
    # Set up sscratch for trap handler
    # This will be the kernel stack when we return from user mode
    csrw sscratch, a2
    
    # Set user entry point in sepc
    csrw sepc, a0
    
    # Set user stack pointer
    mv sp, a1
    
    # Set up sstatus for user mode transition
    # Clear SPP (bit 8) = 0 for user mode
    # Set SPIE (bit 5) = 1 to enable interrupts in user mode
    li t0, (1 << 5)
    csrw sstatus, t0
    
    # Clear all general purpose registers for security
    # Leave only essential registers
    li t0, 0
    li t1, 0
    li t2, 0
    li t3, 0
    li t4, 0
    li t5, 0
    li t6, 0
    li s0, 0
    li s1, 0
    li s2, 0
    li s3, 0
    li s4, 0
    li s5, 0
    li s6, 0
    li s7, 0
    li s8, 0
    li s9, 0
    li s10, 0
    li s11, 0
    li a2, 0
    li a3, 0
    li a4, 0
    li a5, 0
    li a6, 0
    li a7, 0
    li ra, 0
    li gp, 0
    li tp, 0
    
    # Keep a0, a1 for potential user program arguments
    # a0 could be argc, a1 could be argv
    
    # Transition to user mode
    sret
    
    # Should never reach here
    j switch_to_user_mode