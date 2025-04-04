[BITS 16]
[ORG 0x7C00]

start:
    ; セグメントレジスタを初期化
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    ; 画面クリア
    mov ah, 0x00
    mov al, 0x03
    int 0x10

    ; 起動メッセージ表示
    mov si, boot_msg
    call print_string

    ; カーネルをロード（セクタ1から）
    mov ah, 0x02        ; BIOS読み込み関数
    mov al, 8           ; 読み込むセクタ数（4KB=8セクタ分）
    mov ch, 0           ; シリンダ0
    mov cl, 2           ; セクタ2（1から始まる）
    mov dh, 0           ; ヘッド0
    mov dl, 0x80        ; ドライブ（ハードディスク）
    mov bx, 0x1000      ; ロード先アドレス
    int 0x13
    jc load_error       ; エラーならジャンプ

    ; カーネルロード成功のメッセージ表示
    mov si, load_msg
    call print_string

    ; A20ラインを有効化
    call enable_a20
    
    ; プロテクトモードに切り替え
    cli                     ; 割り込み無効化
    lgdt [gdt_descriptor]   ; GDTをロード
    
    ; CR0レジスタのPEビット（最下位ビット）を1に設定
    mov eax, cr0
    or al, 1
    mov cr0, eax
    
    ; プロテクトモードのコードセグメントにジャンプ
    jmp 0x08:protected_mode

load_error:
    mov si, error_msg
    call print_string
    jmp $

; A20ラインを有効化する関数
enable_a20:
    ; キーボードコントローラ経由でA20を有効化
    call a20_wait_input
    mov al, 0xAD        ; キーボードを無効化
    out 0x64, al
    
    call a20_wait_input
    mov al, 0xD0        ; 出力ポートの読み込みを指示
    out 0x64, al
    
    call a20_wait_output
    in al, 0x60
    push ax             ; 元の値を保存
    
    call a20_wait_input
    mov al, 0xD1        ; 出力ポートに書き込みを指示
    out 0x64, al
    
    call a20_wait_input
    pop ax              ; 元の値を復元
    or al, 2            ; A20ビットを設定
    out 0x60, al
    
    call a20_wait_input
    mov al, 0xAE        ; キーボードを有効化
    out 0x64, al
    
    call a20_wait_input
    ret

a20_wait_input:
    ; ステータスレジスタのビット1（入力バッファフル）がクリアされるのを待つ
    in al, 0x64
    test al, 2
    jnz a20_wait_input
    ret

a20_wait_output:
    ; ステータスレジスタのビット0（出力バッファフル）がセットされるのを待つ
    in al, 0x64
    test al, 1
    jz a20_wait_output
    ret

; 文字列表示関数
print_string:
    lodsb               ; SI レジスタから1バイト読み込む
    or al, al           ; ゼロかどうかチェック
    jz .done
    mov ah, 0x0E        ; テレタイプ出力
    int 0x10            ; BIOS呼び出し
    jmp print_string
.done:
    ret

; データ定義
boot_msg: db 'Booting into 32-bit protected mode...', 13, 10, 0
load_msg: db 'Kernel loaded, switching to protected mode...', 13, 10, 0
error_msg: db 'Error loading kernel!', 13, 10, 0

; GDT（グローバル記述子テーブル）
gdt_start:
    ; NULL記述子
    dd 0x0
    dd 0x0
    
    ; コードセグメント: base=0, limit=0xFFFFF, access=0x9A, granularity=0xCF
    dw 0xFFFF           ; Limit (0:15)
    dw 0x0000           ; Base (0:15)
    db 0x00             ; Base (16:23)
    db 0x9A             ; Access (P=1, DPL=0, S=1, E=1, DC=0, RW=1, A=0)
    db 0xCF             ; Granularity (G=1, D/B=1, L=0, AVL=0) + Limit (16:19)
    db 0x00             ; Base (24:31)
    
    ; データセグメント: base=0, limit=0xFFFFF, access=0x92, granularity=0xCF
    dw 0xFFFF           ; Limit (0:15)
    dw 0x0000           ; Base (0:15)
    db 0x00             ; Base (16:23)
    db 0x92             ; Access (P=1, DPL=0, S=1, E=0, DC=0, RW=1, A=0)
    db 0xCF             ; Granularity (G=1, D/B=1, L=0, AVL=0) + Limit (16:19)
    db 0x00             ; Base (24:31)
gdt_end:

; GDT記述子
gdt_descriptor:
    dw gdt_end - gdt_start - 1  ; GDTのサイズ - 1
    dd gdt_start                 ; GDTの物理アドレス

[BITS 32]
protected_mode:
    ; セグメントレジスタを設定
    mov ax, 0x10        ; データセグメントセレクタ（GDTの3番目のエントリ）
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    ; スタックポインタ設定
    mov esp, 0x90000
    
    ; カーネルにジャンプ
    jmp 0x08:0x1000     ; コードセグメントセレクタ:カーネルアドレス

; 512バイトのブートセクタを埋める
times 510 - ($ - $$) db 0
dw 0xAA55  ; ブートシグネチャ
