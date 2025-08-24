# RISC-V context switch implementation
# void context_switch(Context *old, Context *new)
# 
# Context layout (matches full Context struct in process/core.zig):
# 0:   ra (x1)
# 8:   sp (x2)
# 16:  gp (x3)
# 24:  tp (x4)
# 32:  t0 (x5)
# 40:  t1 (x6)
# 48:  t2 (x7)
# 56:  s0 (x8)
# 64:  s1 (x9)
# 72:  a0 (x10)
# 80:  a1 (x11)
# 88:  a2 (x12)
# 96:  a3 (x13)
# 104: a4 (x14)
# 112: a5 (x15)
# 120: a6 (x16)
# 128: a7 (x17)
# 136: s2 (x18)
# 144: s3 (x19)
# 152: s4 (x20)
# 160: s5 (x21)
# 168: s6 (x22)
# 176: s7 (x23)
# 184: s8 (x24)
# 192: s9 (x25)
# 200: s10 (x26)
# 208: s11 (x27)
# 216: t3 (x28)
# 224: t4 (x29)
# 232: t5 (x30)
# 240: t6 (x31)
# 248: satp

.section .text
.global context_switch
.type context_switch, @function

context_switch:
    # a0 = old context pointer
    # a1 = new context pointer

    # Save all registers to old context
    sd ra,   0(a0)   # x1
    sd sp,   8(a0)   # x2
    sd gp,  16(a0)   # x3
    sd tp,  24(a0)   # x4
    sd t0,  32(a0)   # x5
    sd t1,  40(a0)   # x6
    sd t2,  48(a0)   # x7
    sd s0,  56(a0)   # x8
    sd s1,  64(a0)   # x9
    # a0 and a1 are special - save them after we're done using them
    sd a2,  88(a0)   # x12
    sd a3,  96(a0)   # x13
    sd a4, 104(a0)   # x14
    sd a5, 112(a0)   # x15
    sd a6, 120(a0)   # x16
    sd a7, 128(a0)   # x17
    sd s2, 136(a0)   # x18
    sd s3, 144(a0)   # x19
    sd s4, 152(a0)   # x20
    sd s5, 160(a0)   # x21
    sd s6, 168(a0)   # x22
    sd s7, 176(a0)   # x23
    sd s8, 184(a0)   # x24
    sd s9, 192(a0)   # x25
    sd s10, 200(a0)  # x26
    sd s11, 208(a0)  # x27
    sd t3, 216(a0)   # x28
    sd t4, 224(a0)   # x29
    sd t5, 232(a0)   # x30
    sd t6, 240(a0)   # x31

    # Save current SATP
    csrr t0, satp       # read current satp
    sd t0, 248(a0)      # save to context
    
    # Now save a0 and a1 (we can use t0 and t1 as temps)
    mv t0, a0           # save old context pointer
    mv t1, a1           # save new context pointer
    sd t0, 72(a0)       # save a0 to its slot
    sd t1, 80(a0)       # save a1 to its slot

    # Restore all registers from new context
    ld ra,   0(a1)   # x1
    ld sp,   8(a1)   # x2
    ld gp,  16(a1)   # x3
    ld tp,  24(a1)   # x4
    ld t0,  32(a1)   # x5
    ld t1,  40(a1)   # x6
    ld t2,  48(a1)   # x7
    ld s0,  56(a1)   # x8
    ld s1,  64(a1)   # x9
    # Skip a0 and a1 for now - restore them last
    ld a2,  88(a1)   # x12
    ld a3,  96(a1)   # x13
    ld a4, 104(a1)   # x14
    ld a5, 112(a1)   # x15
    ld a6, 120(a1)   # x16
    ld a7, 128(a1)   # x17
    ld s2, 136(a1)   # x18
    ld s3, 144(a1)   # x19
    ld s4, 152(a1)   # x20
    ld s5, 160(a1)   # x21
    ld s6, 168(a1)   # x22
    ld s7, 176(a1)   # x23
    ld s8, 184(a1)   # x24
    ld s9, 192(a1)   # x25
    ld s10, 200(a1)  # x26
    ld s11, 208(a1)  # x27
    ld t3, 216(a1)   # x28
    ld t4, 224(a1)   # x29
    ld t5, 232(a1)   # x30
    ld t6, 240(a1)   # x31

    # Restore new process's SATP
    ld t0, 248(a1)      # load new satp

    # Ensure all memory operations complete before changing page table
    fence rw, rw

    csrw satp, t0       # set satp
    sfence.vma zero, zero  # flush entire TLB

    # Finally restore a0 and a1
    ld a0, 72(a1)    # x10
    ld a1, 80(a1)    # x11

    # Return to new context (ra now points to new process's continuation)
    ret

.size context_switch, . - context_switch
