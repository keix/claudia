# RISC-V kernel entry point
# Bootstrap code for kernel initialization

.section .text.boot
.global _start

_start:
    # Set stack pointer
    # RISC-V stack grows downward, set to end of RAM
    la sp, _stack_top
    
    # Clear GP to prevent GP-relative addressing issues
    li gp, 0
    
    # Save boot parameters from OpenSBI
    # a0 = hartid, a1 = dtb pointer, a2 = initrd address (if provided)
    la t0, boot_hartid
    sd a0, 0(t0)
    la t0, boot_dtb_ptr
    sd a1, 0(t0)
    la t0, boot_initrd_addr
    sd a2, 0(t0)
    
    # Clear BSS section
    la t0, _bss_start
    la t1, _bss_end
clear_bss:
    bgeu t0, t1, clear_bss_done
    sd zero, 0(t0)
    addi t0, t0, 8
    j clear_bss
clear_bss_done:

    # Jump to kernel main (OpenSBI already set us up in S-mode)
    call start

    # If kernel returns, hang
hang:
    wfi
    j hang

.section .data
.global boot_hartid
.global boot_dtb_ptr
.global boot_initrd_addr
boot_hartid:      .dword 0
boot_dtb_ptr:     .dword 0
boot_initrd_addr: .dword 0

.section .bss
.align 16
_stack_bottom:
    .space 0x4000  # 16KB stack
_stack_top:
