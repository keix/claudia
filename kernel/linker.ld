ENTRY(_start)

SECTIONS {
    . = 0x1000;

    .text : {
        *(.text*)
    }

    .rodata : {
        *(.rodata*)
    }

    .data : {
        *(.data*)
    }

    .bss : {
        *(.bss*)
    }

    /* Reserve 4KB for the kernel (same as the original kernel) */
    . = ALIGN(4096);
}
