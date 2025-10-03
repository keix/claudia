# RISC-V context switching
# Minimal implementation - only saves callee-saved registers per RISC-V ABI
# CSRs and page tables are managed by the scheduler

# void context_switch(Context *old, Context *new)
# Context layout (matches minimal Context struct):
# 0:   ra (x1)  - return address
# 8:   sp (x2)  - stack pointer
# 16:  s0 (x8)  - saved register
# 24:  s1 (x9)  - saved register
# 32:  s2 (x18) - saved register
# 40:  s3 (x19) - saved register
# 48:  s4 (x20) - saved register
# 56:  s5 (x21) - saved register
# 64:  s6 (x22) - saved register
# 72:  s7 (x23) - saved register
# 80:  s8 (x24) - saved register
# 88:  s9 (x25) - saved register
# 96:  s10 (x26) - saved register
# 104: s11 (x27) - saved register

.section .text
.global context_switch
.type context_switch, @function

context_switch:
    # a0 = old context pointer
    # a1 = new context pointer

    # Note: Interrupts are already disabled by the scheduler before calling this function
    # Page table switching (satp) is also handled by the scheduler

    # Save callee-saved registers to old context
    sd ra,   0(a0)      # x1  - return address
    sd sp,   8(a0)      # x2  - stack pointer
    sd s0,  16(a0)      # x8  - saved register
    sd s1,  24(a0)      # x9  - saved register
    sd s2,  32(a0)      # x18 - saved register
    sd s3,  40(a0)      # x19 - saved register
    sd s4,  48(a0)      # x20 - saved register
    sd s5,  56(a0)      # x21 - saved register
    sd s6,  64(a0)      # x22 - saved register
    sd s7,  72(a0)      # x23 - saved register
    sd s8,  80(a0)      # x24 - saved register
    sd s9,  88(a0)      # x25 - saved register
    sd s10, 96(a0)      # x26 - saved register
    sd s11, 104(a0)     # x27 - saved register

    # Restore callee-saved registers from new context
    ld ra,   0(a1)      # x1  - return address
    ld sp,   8(a1)      # x2  - stack pointer
    ld s0,  16(a1)      # x8  - saved register
    ld s1,  24(a1)      # x9  - saved register
    ld s2,  32(a1)      # x18 - saved register
    ld s3,  40(a1)      # x19 - saved register
    ld s4,  48(a1)      # x20 - saved register
    ld s5,  56(a1)      # x21 - saved register
    ld s6,  64(a1)      # x22 - saved register
    ld s7,  72(a1)      # x23 - saved register
    ld s8,  80(a1)      # x24 - saved register
    ld s9,  88(a1)      # x25 - saved register
    ld s10, 96(a1)      # x26 - saved register
    ld s11, 104(a1)     # x27 - saved register

    # Return to new context (ra now points to new process's continuation)
    ret

.size context_switch, . - context_switch
