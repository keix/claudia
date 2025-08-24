# RISC-V trap handler
# Handles system calls and exceptions from user mode

.section .text
.global trap_vector
.align 4  # RISC-V requires 4-byte alignment for trap vectors

trap_vector:
    # Check if we came from user mode or kernel mode
    csrr t0, sstatus
    andi t0, t0, (1 << 8)  # Check SPP bit
    bnez t0, kernel_trap   # If SPP=1, came from S-mode (kernel)

user_trap:
    # Came from user mode - swap sp and sscratch
    # sscratch holds kernel stack pointer when in user mode
    csrrw sp, sscratch, sp
    j trap_common

kernel_trap:
    # Came from kernel mode - don't swap stack, keep sscratch unchanged
    # We need to preserve sscratch for user mode return
    nop  # sscratch keeps its value (kernel stack pointer)

trap_common:
    # Save all registers on kernel stack
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

    # Save user sp: depends on where we came from
    csrr t0, sstatus
    andi t0, t0, (1 << 8)  # Check SPP bit
    bnez t0, save_kernel_sp   # If SPP=1, came from kernel

    # Came from user mode - sscratch has user SP
    csrr t0, sscratch
    sd t0, 248(sp)
    j sp_saved

save_kernel_sp:
    # Came from kernel mode - need to save the original SP before we modified it
    # We need to add back the stack frame size to get original SP
    addi t0, sp, 264
    sd t0, 248(sp)

sp_saved:

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

    # Check if we're returning to user mode or kernel mode
    csrr t0, sstatus
    andi t0, t0, (1 << 8)  # Check SPP bit
    bnez t0, kernel_return  # If SPP=1, returning to S-mode (kernel)

user_return:
    # Returning to user mode - restore user sp to sscratch
    ld t0, 248(sp)
    csrw sscratch, t0
    j restore_regs

kernel_return:
    # Returning to kernel mode - sscratch should keep kernel stack
    # Don't modify sscratch

restore_regs:

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

    # Check if we're returning to user mode
    csrr t0, sstatus
    andi t0, t0, (1 << 8)  # Check SPP bit
    bnez t0, kernel_sret   # If SPP=1, returning to kernel - don't swap stacks

    # Returning to user mode - swap sp and sscratch again
    csrrw sp, sscratch, sp

kernel_sret:
    # Return to user or kernel mode
    sret

# Make trap_vector accessible from Zig
.global trap_vector_addr
trap_vector_addr:
    .quad trap_vector