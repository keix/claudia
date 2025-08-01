.section .text.boot
.global _start

_start:
    # Set stack pointer
    # RISC-V stack grows downward, set to end of RAM
    la sp, _stack_top
    
    # Clear BSS section
    la t0, _bss_start
    la t1, _bss_end
clear_bss:
    bgeu t0, t1, clear_bss_done
    sd zero, 0(t0)
    addi t0, t0, 8
    j clear_bss
clear_bss_done:

    # Jump to kernel main
    call start

    # If kernel returns, hang
hang:
    wfi
    j hang

.section .bss
.align 16
_stack_bottom:
    .space 0x4000  # 16KB stack
_stack_top:
