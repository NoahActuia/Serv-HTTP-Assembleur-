%define SYS_READ        0
%define SYS_WRITE       1
%define SYS_OPEN        2
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
%define O_RDONLY        0

section .data

    srv_addr:
        dw  AF_INET
        dw  0x901F
        dd  0
        times 8 db 0

    opt_reuseaddr   dd  1

    msg_start       db  "Serveur HTTP demarre sur le port 8080...", 10
    msg_start_len   equ $ - msg_start

    log_prefix_get  db  "[LOG] GET ", 0
    log_prefix_get_len equ $ - log_prefix_get - 1

    log_prefix_post db  "[LOG] POST ", 0
    log_prefix_post_len equ $ - log_prefix_post - 1

    log_body_prefix db  " body=", 0
    log_body_prefix_len equ $ - log_body_prefix - 1

    log_rejected    db  "[LOG] 405 Method Not Allowed", 10
    log_rejected_len equ $ - log_rejected

    newline         db  10

    str_get         db  "GET ", 0
    str_get_len     equ 4

    str_post        db  "POST ", 0
    str_post_len    equ 5

    hdr_content_len db  "Content-Length: ", 0
    hdr_content_len_len equ 16

    path_root       db  "/", 0
    path_about      db  "/about", 0
    path_message    db  "/message", 0

    file_index      db  "pages/index.html", 0
    file_about      db  "pages/about.html", 0
    file_404        db  "pages/404.html", 0
    file_post_ok    db  "pages/post_ok.html", 0

    resp_405_hdr:
        db  "HTTP/1.1 405 Method Not Allowed", 13, 10
        db  "Content-Type: text/plain", 13, 10
        db  "Connection: close", 13, 10
        db  13, 10
        db  "405 Method Not Allowed", 13, 10
    resp_405_len    equ $ - resp_405_hdr

    resp_404_hdr:
        db  "HTTP/1.1 404 Not Found", 13, 10
        db  "Content-Type: text/html; charset=utf-8", 13, 10
        db  "Connection: close", 13, 10
        db  13, 10
    resp_404_hdr_len equ $ - resp_404_hdr

    resp_200_hdr:
        db  "HTTP/1.1 200 OK", 13, 10
        db  "Content-Type: text/html; charset=utf-8", 13, 10
        db  "Connection: close", 13, 10
        db  13, 10
    resp_200_hdr_len equ $ - resp_200_hdr

section .bss
    req_buf         resb 4096
    path_buf        resb 256
    file_buf        resb 8192
    req_len         resq 1
    method_is_post  resb 1
    body_ptr        resq 1
    body_len        resq 1

section .text
    global _start

; str_len — calcule la longueur d'une chaine null-terminee
; entree : rdi = chaine
; sortie : rax = longueur
str_len:
    xor     rax, rax
.loop:
    cmp     byte [rdi + rax], 0
    je      .done
    inc     rax
    jmp     .loop
.done:
    ret

; log_request — affiche la methode, le chemin et le corps POST dans le terminal
log_request:
    cmp     byte [method_is_post], 1
    je      .post_prefix
    mov     rsi, log_prefix_get
    mov     rdx, log_prefix_get_len
    jmp     .write_prefix
.post_prefix:
    mov     rsi, log_prefix_post
    mov     rdx, log_prefix_post_len
.write_prefix:
    mov     rax, SYS_WRITE
    mov     rdi, 1
    syscall

    mov     rdi, path_buf
    call    str_len
    mov     rdx, rax
    mov     rax, SYS_WRITE
    mov     rdi, 1
    mov     rsi, path_buf
    syscall

    cmp     byte [method_is_post], 1
    jne     .newline
    cmp     qword [body_len], 0
    je      .newline

    mov     rax, SYS_WRITE
    mov     rdi, 1
    mov     rsi, log_body_prefix
    mov     rdx, log_body_prefix_len
    syscall

    mov     rax, SYS_WRITE
    mov     rdi, 1
    mov     rsi, [body_ptr]
    mov     rdx, [body_len]
    syscall

.newline:
    mov     rax, SYS_WRITE
    mov     rdi, 1
    mov     rsi, newline
    mov     rdx, 1
    syscall
    ret

; log_rejected_request — affiche un rejet de methode non-GET
log_rejected_request:
    mov     rax, SYS_WRITE
    mov     rdi, 1
    mov     rsi, log_rejected
    mov     rdx, log_rejected_len
    syscall
    ret

; str_eq — compare path_buf avec une chaine null-terminee
; entree : rdi = chaine attendue
; sortie : rax = 1 si egal, 0 sinon
str_eq:
    mov     rsi, path_buf
.loop:
    movzx   eax, byte [rsi]
    movzx   edx, byte [rdi]
    cmp     al, dl
    jne     .neq
    test    al, al
    jz      .eq
    inc     rsi
    inc     rdi
    jmp     .loop
.eq:
    mov     rax, 1
    ret
.neq:
    xor     rax, rax
    ret

; send_body — envoie en-tete HTTP + corps depuis file_buf
; entree : r13 = fd client, r14 = taille corps, r15 = code en-tete (200 ou 404)
send_body:
    cmp     r15b, 4
    je      .hdr_404
    mov     rax, SYS_WRITE
    mov     rdi, r13
    mov     rsi, resp_200_hdr
    mov     rdx, resp_200_hdr_len
    syscall
    jmp     .write_body
.hdr_404:
    mov     rax, SYS_WRITE
    mov     rdi, r13
    mov     rsi, resp_404_hdr
    mov     rdx, resp_404_hdr_len
    syscall
.write_body:
    mov     rax, SYS_WRITE
    mov     rdi, r13
    mov     rsi, file_buf
    mov     rdx, r14
    syscall
    ret

; serve_file — lit un fichier HTML et l'envoie au client
; entree : rdi = chemin fichier, r13 = fd client, r15b = code HTTP (0=200, 4=404)
; sortie : rax = 0 si succes, rax = -1 si echec
serve_file:
    push    rdi
    push    r15
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    pop     r15
    pop     rdi
    test    rax, rax
    js      .fail
    mov     r14, rax

    mov     rax, SYS_READ
    mov     rdi, r14
    mov     rsi, file_buf
    mov     rdx, 8192
    syscall
    test    rax, rax
    jle     .close_fail
    mov     rbx, rax

    mov     rax, SYS_CLOSE
    mov     rdi, r14
    syscall

    mov     r14, rbx
    call    send_body
    xor     rax, rax
    ret

.close_fail:
    mov     rax, SYS_CLOSE
    mov     rdi, r14
    syscall
.fail:
    mov     rax, -1
    ret

; send_404 — sert pages/404.html depuis le disque
; entree : r13 = fd client
send_404:
    mov     rdi, file_404
    mov     r15b, 4
    call    serve_file
    ret

; route_post_request — dispatch des requetes POST
; entree : r13 = fd client
route_post_request:
    mov     rdi, path_message
    call    str_eq
    test    rax, rax
    jnz     .serve_post_ok

    call    send_404
    ret

.serve_post_ok:
    mov     rdi, file_post_ok
    xor     r15b, r15b
    call    serve_file
    test    rax, rax
    jnz     send_404
    ret

; route_request — dispatch des requetes GET
; entree : r13 = fd client
route_request:
    mov     rdi, path_root
    call    str_eq
    test    rax, rax
    jnz     .serve_index

    mov     rdi, path_about
    call    str_eq
    test    rax, rax
    jnz     .serve_about

    call    send_404
    ret

.serve_index:
    mov     rdi, file_index
    xor     r15b, r15b
    call    serve_file
    test    rax, rax
    jnz     send_404
    ret

.serve_about:
    mov     rdi, file_about
    xor     r15b, r15b
    call    serve_file
    test    rax, rax
    jnz     send_404
    ret

; parse_content_length — lit Content-Length dans req_buf
; sortie : rax = longueur du corps, 0 si absent
parse_content_length:
    mov     rsi, req_buf
    mov     rcx, [req_len]
.search:
    cmp     rcx, hdr_content_len_len
    jb      .not_found
    mov     rdi, hdr_content_len
    mov     rbx, hdr_content_len_len
.cmp_hdr:
    test    rbx, rbx
    jz      .parse_digits
    movzx   eax, byte [rsi]
    movzx   edx, byte [rdi]
    cmp     al, dl
    jne     .next
    inc     rsi
    inc     rdi
    dec     rbx
    dec     rcx
    jmp     .cmp_hdr
.parse_digits:
    xor     rax, rax
.digit_loop:
    cmp     rcx, 0
    je      .done
    movzx   edx, byte [rsi]
    cmp     dl, '0'
    jb      .done
    cmp     dl, '9'
    ja      .done
    imul    rax, 10
    sub     dl, '0'
    add     rax, rdx
    inc     rsi
    dec     rcx
    jmp     .digit_loop
.next:
    inc     rsi
    dec     rcx
    jmp     .search
.not_found:
    xor     rax, rax
.done:
    ret

; find_body_start — trouve le debut du corps HTTP apres les en-tetes
; sortie : rax = pointeur corps, rax = 0 si non trouve
find_body_start:
    mov     rsi, req_buf
    mov     rcx, [req_len]
    cmp     rcx, 4
    jb      .not_found
.scan:
    cmp     byte [rsi], 13
    jne     .advance
    cmp     byte [rsi + 1], 10
    jne     .advance
    cmp     byte [rsi + 2], 13
    jne     .advance
    cmp     byte [rsi + 3], 10
    jne     .advance
    lea     rax, [rsi + 4]
    ret
.advance:
    inc     rsi
    dec     rcx
    cmp     rcx, 4
    jae     .scan
.not_found:
    xor     rax, rax
    ret

; read_post_body — lit le corps POST complet dans req_buf
; entree : r13 = fd client
read_post_body:
    xor     qword [body_len], 0
    xor     qword [body_ptr], 0

    call    find_body_start
    test    rax, rax
    jz      .done
    mov     rbx, rax

    push    rbx
    call    parse_content_length
    pop     rbx
    mov     r14, rax
    test    r14, r14
    jz      .done

    mov     rax, rbx
    sub     rax, req_buf
    mov     rcx, [req_len]
    sub     rcx, rax
    jbe     .read_more
    cmp     rcx, r14
    cmova   rcx, r14
    jmp     .store_body
.read_more:
    xor     rcx, rcx
.store_body:

    mov     [body_ptr], rbx
    mov     [body_len], rcx

    cmp     rcx, r14
    jae     .done

    mov     rsi, rbx
    add     rsi, rcx
    mov     rdx, r14
    sub     rdx, rcx
    mov     rax, SYS_READ
    mov     rdi, r13
    syscall
    test    rax, rax
    jle     .done
    add     [body_len], rax
    add     [req_len], rax
.done:
    ret

; parse_request — verifie GET/POST et extrait le chemin dans path_buf
; sortie : rax = 0 si methode supportee, rax = -1 sinon
parse_request:
    mov     byte [method_is_post], 0

    mov     rsi, req_buf
    mov     rdi, str_get
    mov     rcx, str_get_len
.check_method:
    test    rcx, rcx
    jz      .extract_path
    movzx   eax, byte [rsi]
    movzx   edx, byte [rdi]
    cmp     al, dl
    jne     .try_post
    inc     rsi
    inc     rdi
    dec     rcx
    jmp     .check_method

.try_post:
    mov     byte [method_is_post], 1
    mov     rsi, req_buf
    mov     rdi, str_post
    mov     rcx, str_post_len
.check_post:
    test    rcx, rcx
    jz      .extract_path
    movzx   eax, byte [rsi]
    movzx   edx, byte [rdi]
    cmp     al, dl
    jne     .unsupported
    inc     rsi
    inc     rdi
    dec     rcx
    jmp     .check_post

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
    jae     .unsupported
    mov     [rdi], al
    inc     rsi
    inc     rdi
    inc     rcx
    jmp     .copy_path

.path_done:
    mov     byte [rdi], 0
    xor     rax, rax
    ret

.unsupported:
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
    test    rax, rax
    jle     .close_conn
    mov     [req_len], rax

    call    parse_request
    test    rax, rax
    jnz     .send_405

    cmp     byte [method_is_post], 1
    je      .handle_post

    call    log_request
    call    route_request
    jmp     .close_conn

.handle_post:
    call    read_post_body
    call    log_request
    call    route_post_request
    jmp     .close_conn

.send_405:
    call    log_rejected_request
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
