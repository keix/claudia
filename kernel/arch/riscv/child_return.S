# Child process return to user mode
# This is a pure assembly implementation to avoid any compiler-generated GP usage

.section .text
.global child_return_to_user
.align 4

# child_return_to_user(trap_frame)
# a0 = pointer to trap frame
child_return_to_user:
    # Clear GP to prevent any GP-relative addressing
    li gp, 0
    
    # Load sepc from frame
    ld t0, 0(a0)
    csrw sepc, t0
    
    # Load user sp to sscratch
    ld t0, 248(a0)
    csrw sscratch, t0
    
    # Set sstatus for user mode return
    li t0, 0x22  # SPIE=1, SPP=0
    csrw sstatus, t0
    
    # Restore all registers from trap frame
    ld ra, 8(a0)
    # Skip gp (16) - keep it as 0
    ld tp, 24(a0)
    ld t0, 32(a0)
    ld t1, 40(a0)
    ld t2, 48(a0)
    ld s0, 56(a0)
    ld s1, 64(a0)
    # Skip a0 (72) for now - will load it last
    ld a1, 80(a0)
    ld a2, 88(a0)
    ld a3, 96(a0)
    ld a4, 104(a0)
    ld a5, 112(a0)
    ld a6, 120(a0)
    ld a7, 128(a0)
    ld s2, 136(a0)
    ld s3, 144(a0)
    ld s4, 152(a0)
    ld s5, 160(a0)
    ld s6, 168(a0)
    ld s7, 176(a0)
    ld s8, 184(a0)
    ld s9, 192(a0)
    ld s10, 200(a0)
    ld s11, 208(a0)
    ld t3, 216(a0)
    ld t4, 224(a0)
    ld t5, 232(a0)
    ld t6, 240(a0)
    
    # Load a0 last (fork return value = 0)
    li a0, 0  # Force a0 to 0 for child
    
    # Swap to user stack
    csrrw sp, sscratch, sp
    
    # Return to user mode
    sret