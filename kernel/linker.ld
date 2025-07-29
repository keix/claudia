ENTRY(_start)

SECTIONS
{
    /* QEMU RISC-V virt machine loads kernel at 0x80200000 */
    . = 0x80200000;

    .text :
    {
        *(.text.boot)
        *(.text .text.*)
    }

    .rodata :
    {
        *(.rodata .rodata.*)
    }

    .data :
    {
        *(.data .data.*)
    }

    .bss :
    {
        . = ALIGN(8);
        _bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(8);
        _bss_end = .;
    }

    _end = .;
}