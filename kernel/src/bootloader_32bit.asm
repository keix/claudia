[BITS 16]
[ORG 0x7C00]

start:
    ; Initialize segment registers
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    ; Clear screen
    mov ah, 0x00
    mov al, 0x03
    int 0x10

    ; Print boot message
    mov si, boot_msg
    call print_string

    ; Load kernel from sector 1 (512 * 8 = 4KB)
    mov ah, 0x02        ; BIOS read function
    mov al, 8           ; Number of sectors to read
    mov ch, 0           ; Cylinder 0
    mov cl, 2           ; Sector 2 (starts from 1)
    mov dh, 0           ; Head 0
    mov dl, 0x80        ; Drive 0x80 (HDD)
    mov bx, 0x1000      ; Load address
    int 0x13
    jc load_error       ; Jump if error

    ; Print load success message
    mov si, load_msg
    call print_string

    ; Enable A20 line
    call enable_a20

    ; Switch to protected mode
    cli                     ; Disable interrupts
    lgdt [gdt_descriptor]   ; Load GDT

    ; Set PE bit in CR0 to enable protected mode
    mov eax, cr0
    or al, 1
    mov cr0, eax

    ; Far jump to protected mode
    jmp 0x08:protected_mode

load_error:
    mov si, error_msg
    call print_string
    jmp $

; Enable A20 line via keyboard controller
enable_a20:
    call a20_wait_input
    mov al, 0xAD        ; Disable keyboard
    out 0x64, al

    call a20_wait_input
    mov al, 0xD0        ; Request output port value
    out 0x64, al

    call a20_wait_output
    in al, 0x60
    push ax             ; Save original value

    call a20_wait_input
    mov al, 0xD1        ; Prepare to write output port
    out 0x64, al

    call a20_wait_input
    pop ax              ; Restore original value
    or al, 2            ; Set A20 bit
    out 0x60, al

    call a20_wait_input
    mov al, 0xAE        ; Enable keyboard
    out 0x64, al

    call a20_wait_input
    ret

; Wait until input buffer is empty (bit 1 cleared)
a20_wait_input:
    in al, 0x64
    test al, 2
    jnz a20_wait_input
    ret

; Wait until output buffer is full (bit 0 set)
a20_wait_output:
    in al, 0x64
    test al, 1
    jz a20_wait_output
    ret

; Print string using BIOS interrupt 0x10
print_string:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp print_string
.done:
    ret

; Messages
boot_msg: db 'Booting into 32-bit protected mode...', 13, 10, 0
load_msg: db 'Kernel loaded, switching to protected mode...', 13, 10, 0
error_msg: db 'Error loading kernel!', 13, 10, 0

; Global Descriptor Table (GDT)
gdt_start:
    ; Null descriptor
    dd 0x0
    dd 0x0

    ; Code segment descriptor
    dw 0xFFFF           ; Limit (0:15)
    dw 0x0000           ; Base (0:15)
    db 0x00             ; Base (16:23)
    db 0x9A             ; Access
    db 0xCF             ; Granularity + Limit (16:19)
    db 0x00             ; Base (24:31)

    ; Data segment descriptor
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x92
    db 0xCF
    db 0x00
gdt_end:

; GDT descriptor
gdt_descriptor:
    dw gdt_end - gdt_start - 1  ; Size - 1
    dd gdt_start                ; Address

[BITS 32]
protected_mode:
    ; Set segment registers
    mov ax, 0x10        ; Data segment selector
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; Set stack pointer
    mov esp, 0x90000

    ; Jump to kernel entry point
    jmp 0x08:0x1000     ; CS:IP = kernel entry

; Pad to 512 bytes and add boot signature
times 510 - ($ - $$) db 0
dw 0xAA55
