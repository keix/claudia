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
    
    /* カーネルのサイズを4KBに確保する（元のカーネルと同様） */
    . = ALIGN(4096);
}
