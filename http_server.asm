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

section .text
    global _start

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

    mov     rax, SYS_WRITE
    mov     rdi, r13
    mov     rsi, http_resp
    mov     rdx, http_resp_len
    syscall

    mov     rax, SYS_CLOSE
    mov     rdi, r13
    syscall

    jmp     .loop

.fatal:
    mov     rax, SYS_EXIT
    mov     rdi, 1
    syscall
