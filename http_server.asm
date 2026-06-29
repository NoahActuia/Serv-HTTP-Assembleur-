%define SYS_READ        0
%define SYS_WRITE       1
%define SYS_CLOSE       3
%define SYS_SOCKET      41
%define SYS_ACCEPT      43
%define SYS_BIND        49
%define SYS_LISTEN      50
%define SYS_SETSOCKOPT  54
%define SYS_EXIT        60

%define AF_INET         2
%define SOCK_STREAM     1
%define SOL_SOCKET      1
%define SO_REUSEADDR    2

section .data

    srv_addr:
        dw  AF_INET
        dw  0x901F
        dd  0
        times 8 db 0

    opt_reuseaddr   dd  1

    msg_start       db  "Serveur HTTP demarre sur le port 8080...", 10
    msg_start_len   equ $ - msg_start

    str_get         db  "GET ", 0
    str_get_len     equ 4

    resp_405_hdr:
        db  "HTTP/1.1 405 Method Not Allowed", 13, 10
        db  "Content-Type: text/plain", 13, 10
        db  "Connection: close", 13, 10
        db  13, 10
        db  "405 Method Not Allowed", 13, 10
    resp_405_len    equ $ - resp_405_hdr

    http_resp:
        db  "HTTP/1.1 200 OK", 13, 10
        db  "Content-Type: text/html; charset=utf-8", 13, 10
        db  "Connection: close", 13, 10
        db  13, 10
        db  "<!DOCTYPE html>", 13, 10
        db  "<html>", 13, 10
        db  "<head>", 13, 10
        db  "  <meta charset='utf-8'>", 13, 10
        db  "  <title>Serveur HTTP ASM</title>", 13, 10
        db  "  <style>", 13, 10
        db  "    body { font-family: monospace; max-width: 600px;", 13, 10
        db  "           margin: 60px auto; background: #1e1e2e; color: #cdd6f4; }", 13, 10
        db  "    h1   { color: #89b4fa; }", 13, 10
        db  "    p    { color: #a6e3a1; }", 13, 10
        db  "    code { color: #f38ba8; }", 13, 10
        db  "  </style>", 13, 10
        db  "</head>", 13, 10
        db  "<body>", 13, 10
        db  "  <h1>Bonjour depuis l'assembleur !</h1>", 13, 10
        db  "  <p>Ce serveur HTTP tourne en <code>NASM x86-64</code> pur.</p>", 13, 10
        db  "  <p>Aucune libc, aucun framework — que des syscalls.</p>", 13, 10
        db  "</body>", 13, 10
        db  "</html>", 13, 10
    http_resp_len   equ $ - http_resp

section .bss
    req_buf     resb 4096
    path_buf    resb 256

section .text
    global _start

; parse_get — verifie "GET " et extrait le chemin dans path_buf
; entree : req_buf contient la requete
; sortie : rax = 0 si GET valide, rax = -1 sinon
parse_get:
    mov     rsi, req_buf
    mov     rdi, str_get
    mov     rcx, str_get_len
.check_get:
    test    rcx, rcx
    jz      .extract_path
    movzx   eax, byte [rsi]
    movzx   edx, byte [rdi]
    cmp     al, dl
    jne     .not_get
    inc     rsi
    inc     rdi
    dec     rcx
    jmp     .check_get

.extract_path:
    mov     rdi, path_buf
    xor     rcx, rcx
.copy_path:
    movzx   eax, byte [rsi]
    cmp     al, ' '
    je      .path_done
    cmp     al, '?'
    je      .path_done
    cmp     al, 13
    je      .path_done
    cmp     al, 10
    je      .path_done
    cmp     al, 0
    je      .path_done
    cmp     rcx, 255
    jae     .not_get
    mov     [rdi], al
    inc     rsi
    inc     rdi
    inc     rcx
    jmp     .copy_path

.path_done:
    mov     byte [rdi], 0
    xor     rax, rax
    ret

.not_get:
    mov     rax, -1
    ret

_start:

    mov     rax, SYS_SOCKET
    mov     rdi, AF_INET
    mov     rsi, SOCK_STREAM
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .fatal
    mov     r12, rax

    mov     rax, SYS_SETSOCKOPT
    mov     rdi, r12
    mov     rsi, SOL_SOCKET
    mov     rdx, SO_REUSEADDR
    mov     r10, opt_reuseaddr
    mov     r8,  4
    syscall

    mov     rax, SYS_BIND
    mov     rdi, r12
    mov     rsi, srv_addr
    mov     rdx, 16
    syscall
    test    rax, rax
    jnz     .fatal

    mov     rax, SYS_LISTEN
    mov     rdi, r12
    mov     rsi, 10
    syscall
    test    rax, rax
    jnz     .fatal

    mov     rax, SYS_WRITE
    mov     rdi, 1
    mov     rsi, msg_start
    mov     rdx, msg_start_len
    syscall

.loop:
    mov     rax, SYS_ACCEPT
    mov     rdi, r12
    xor     rsi, rsi
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .loop
    mov     r13, rax

    mov     rax, SYS_READ
    mov     rdi, r13
    mov     rsi, req_buf
    mov     rdx, 4096
    syscall

    call    parse_get
    test    rax, rax
    jnz     .send_405

    mov     rax, SYS_WRITE
    mov     rdi, r13
    mov     rsi, http_resp
    mov     rdx, http_resp_len
    syscall
    jmp     .close_conn

.send_405:
    mov     rax, SYS_WRITE
    mov     rdi, r13
    mov     rsi, resp_405_hdr
    mov     rdx, resp_405_len
    syscall

.close_conn:
    mov     rax, SYS_CLOSE
    mov     rdi, r13
    syscall

    jmp     .loop

.fatal:
    mov     rax, SYS_EXIT
    mov     rdi, 1
    syscall
