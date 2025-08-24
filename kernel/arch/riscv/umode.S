# User mode transition for RISC-V
# Provides one-way transition from S-mode to U-mode

.section .text
.global switch_to_user_mode
.align 4

# switch_to_user_mode_safe(entry_point, user_stack, kernel_stack, satp_val)
# a0 = user entry point (sepc)
# a1 = user stack pointer  
# a2 = kernel stack pointer
# a3 = SATP value for user page table
switch_to_user_mode:
# CRITICAL: Switch to kernel stack BEFORE changing page tables
mv sp, a2

# Set up trap vector and sscratch for proper trap handling
la t0, trap_vector # Make sure stvec points to our trap handler
csrw stvec, t0
csrw sscratch, a2  # Kernel stack for trap handler (CRITICAL)

# Switch to user page table - this is the dangerous moment
csrw satp, a3
sfence.vma

# From this point on, we must not access any data that isn't mapped in both PTs

# Set user entry point in sepc
csrw sepc, a0

# Set up sstatus for user mode transition
csrr t0, sstatus
li t1, ~(1 << 8)  # Mask to clear SPP
and t0, t0, t1# Clear SPP (user mode)
li t1, (1 << 5)   # Set SPIE (enable interrupts)
or t0, t0, t1
csrw sstatus, t0

# Set user stack pointer just before transition
mv sp, a1

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
