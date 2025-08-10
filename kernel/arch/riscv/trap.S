# RISC-V trap handler
# Handles system calls and exceptions from user mode

.section .text
.global trap_vector
.align 4  # RISC-V requires 4-byte alignment for trap vectors

trap_vector:
    # Swap sp and sscratch
    # sscratch holds kernel stack pointer when in user mode
    csrrw sp, sscratch, sp
    
    # Save all user registers on kernel stack
    addi sp, sp, -264
    
    # Save general purpose registers
    sd ra,   8(sp)
    sd gp,  16(sp)
    sd tp,  24(sp)
    sd t0,  32(sp)
    sd t1,  40(sp)
    sd t2,  48(sp)
    sd s0,  56(sp)
    sd s1,  64(sp)
    sd a0,  72(sp)
    sd a1,  80(sp)
    sd a2,  88(sp)
    sd a3,  96(sp)
    sd a4, 104(sp)
    sd a5, 112(sp)
    sd a6, 120(sp)
    sd a7, 128(sp)
    sd s2, 136(sp)
    sd s3, 144(sp)
    sd s4, 152(sp)
    sd s5, 160(sp)
    sd s6, 168(sp)
    sd s7, 176(sp)
    sd s8, 184(sp)
    sd s9, 192(sp)
    sd s10, 200(sp)
    sd s11, 208(sp)
    sd t3, 216(sp)
    sd t4, 224(sp)
    sd t5, 232(sp)
    sd t6, 240(sp)
    
    # Save user sp from sscratch
    csrr t0, sscratch
    sd t0, 248(sp)
    
    # Save trap info
    csrr t0, sepc
    csrr t1, scause
    csrr t2, stval
    sd t0, 0(sp)    # epc at offset 0
    sd t1, 256(sp)  # cause
    sd t2, 264(sp)  # tval
    
    # Call C trap handler
    mv a0, sp  # Pass trap frame pointer
    call trapHandler
    
    # Restore trap info
    ld t0, 0(sp)
    csrw sepc, t0
    
    # Restore user sp to sscratch
    ld t0, 248(sp)
    csrw sscratch, t0
    
    # Restore general purpose registers
    ld ra,   8(sp)
    ld gp,  16(sp)
    ld tp,  24(sp)
    ld t0,  32(sp)
    ld t1,  40(sp)
    ld t2,  48(sp)
    ld s0,  56(sp)
    ld s1,  64(sp)
    ld a0,  72(sp)
    ld a1,  80(sp)
    ld a2,  88(sp)
    ld a3,  96(sp)
    ld a4, 104(sp)
    ld a5, 112(sp)
    ld a6, 120(sp)
    ld a7, 128(sp)
    ld s2, 136(sp)
    ld s3, 144(sp)
    ld s4, 152(sp)
    ld s5, 160(sp)
    ld s6, 168(sp)
    ld s7, 176(sp)
    ld s8, 184(sp)
    ld s9, 192(sp)
    ld s10, 200(sp)
    ld s11, 208(sp)
    ld t3, 216(sp)
    ld t4, 224(sp)
    ld t5, 232(sp)
    ld t6, 240(sp)
    
    addi sp, sp, 264
    
    # Swap sp and sscratch again
    csrrw sp, sscratch, sp
    
    # Return to user mode
    sret

# Make trap_vector accessible from Zig
.global trap_vector_addr
trap_vector_addr:
    .quad trap_vector