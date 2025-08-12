# RISC-V context switch implementation
# void context_switch(Context *old, Context *new)
# 
# Context layout (matches simplified Context struct in process/core.zig):
# 0:  ra
# 8:  sp  
# 16: s0/fp
# 24: s1
# 32: s2
# 40: s3
# 48: s4
# 56: s5
# 64: s6
# 72: s7
# 80: s8
# 88: s9
# 96: s10
# 104: s11

.section .text
.global context_switch
.type context_switch, @function

context_switch:
    # a0 = old context pointer
    # a1 = new context pointer
    
    # Save current context to old (callee-saved registers only)
    sd ra, 0(a0)        # save return address
    sd sp, 8(a0)        # save stack pointer
    sd s0, 16(a0)       # save s0/fp
    sd s1, 24(a0)       # save s1
    sd s2, 32(a0)       # save s2
    sd s3, 40(a0)       # save s3
    sd s4, 48(a0)       # save s4
    sd s5, 56(a0)       # save s5
    sd s6, 64(a0)       # save s6
    sd s7, 72(a0)       # save s7
    sd s8, 80(a0)       # save s8
    sd s9, 88(a0)       # save s9
    sd s10, 96(a0)      # save s10
    sd s11, 104(a0)     # save s11
    
    # Restore context from new
    ld ra, 0(a1)        # restore return address
    ld sp, 8(a1)        # restore stack pointer
    ld s0, 16(a1)       # restore s0/fp
    ld s1, 24(a1)       # restore s1
    ld s2, 32(a1)       # restore s2
    ld s3, 40(a1)       # restore s3
    ld s4, 48(a1)       # restore s4
    ld s5, 56(a1)       # restore s5
    ld s6, 64(a1)       # restore s6
    ld s7, 72(a1)       # restore s7
    ld s8, 80(a1)       # restore s8
    ld s9, 88(a1)       # restore s9
    ld s10, 96(a1)      # restore s10
    ld s11, 104(a1)     # restore s11
    
    # Return to new context (ra now points to new process's continuation)
    ret

.size context_switch, . - context_switch