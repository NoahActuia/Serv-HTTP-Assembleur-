; ============================================================
;  Serveur HTTP en assembleur NASM x86-64 (Linux, syscalls)
;  Port 8080 — GET + POST, pages HTML lues depuis le disque
; ============================================================

; numeros des syscalls linux + constantes reseau/fichiers
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

; types de reponse HTTP - ça envoie un dès header HTTP que ce soit HTML, CSS, JSON ou 404
%define MIME_HTML       0       ; pages HTML 
%define MIME_CSS        1       ; feuille de style
%define MIME_PLAIN      2       ; JSON sur /status
%define MIME_404        4       ; page 404

; ------------------------------------------------------------
;  Donnees fixes : config reseau, messages, routes, reponses
; ------------------------------------------------------------
section .data

    ; adresse du serveur : IPv4, port 8080 (0x901F = htons(8080)), toutes interfaces
    srv_addr:
        dw  AF_INET
        dw  0x901F
        dd  0
        times 8 db 0

    opt_reuseaddr   dd  1          ; evite "Address already in use" au relancement

    msg_start       db  "Serveur HTTP demarre sur le port 8080...", 10
    msg_start_len   equ $ - msg_start

    ; prefixes pour les logs dans le terminal (bonus du sujet)
    log_prefix_get  db  "[LOG] GET ", 0
    log_prefix_get_len equ $ - log_prefix_get - 1

    log_prefix_post db  "[LOG] POST ", 0
    log_prefix_post_len equ $ - log_prefix_post - 1

    log_body_prefix db  " body=", 0
    log_body_prefix_len equ $ - log_body_prefix - 1

    log_rejected    db  "[LOG] 405 Method Not Allowed", 10
    log_rejected_len equ $ - log_rejected

    newline         db  10

    ; --------------------------------------------------------
    ; constantes pour parser et router les requetes HTTP
    ; --------------------------------------------------------

    ; texte attendu au début de la requête : "GET /" ou "POST /"
    str_get         db  "GET ", 0
    str_get_len     equ 4

    str_post        db  "POST ", 0
    str_post_len    equ 5

    ; pour lire la taille du corps POST dans les headers
    hdr_content_len db  "Content-Length: ", 0
    hdr_content_len_len equ 16

    ; URLs qu'on reconnait (comparees avec path_buf apres parsing)
    path_root       db  "/", 0
    path_status     db  "/status", 0
    path_css        db  "/style.css", 0
    path_message    db  "/message", 0

    ; chemins des fichiers lus sur le disque (qui fait partie du bonus du sujet)
    file_index      db  "pages/index.html", 0
    file_404        db  "pages/404.html", 0
    file_post_ok    db  "pages/post_ok.html", 0
    file_css        db  "pages/style.css", 0

    ; reponse JSON de /status (pas de fichier, copie directe en memoire)
    status_body     db  '{"status":"online","server":"ASM-HTTP/1.1","port":8080}', 0
    status_body_len equ $ - status_body - 1

    ; headers HTTP deja ecrits en .data — on evite de les construire a la volee
    ; 13,10 = \r\n obligatoire en HTTP entre chaque ligne
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

    resp_200_css_hdr:
        db  "HTTP/1.1 200 OK", 13, 10
        db  "Content-Type: text/css; charset=utf-8", 13, 10
        db  "Connection: close", 13, 10
        db  13, 10
    resp_200_css_hdr_len equ $ - resp_200_css_hdr

    resp_200_plain_hdr:
        db  "HTTP/1.1 200 OK", 13, 10
        db  "Content-Type: application/json; charset=utf-8", 13, 10
        db  "Connection: close", 13, 10
        db  13, 10
    resp_200_plain_hdr_len equ $ - resp_200_plain_hdr

; ------------------------------------------------------------
;  Variables non initialisees (buffers + etat de la requete)
; ------------------------------------------------------------
section .bss
    req_buf         resb 4096     ;  requete brute lue depuis le client
    path_buf        resb 256      ;  chemin extrait par parse_request
    file_buf        resb 32768    ;  contenu HTML/CSS avant envoi au client
    req_len         resq 1        ;  nb d'octets dans req_buf
    method_is_post  resb 1        ;  0=GET, 1=POST
    body_ptr        resq 1        ;  ou commence le corps POST
    body_len        resq 1        ;  taille du corps POST

section .text
    global _start

; ------------------------------------------------------------
;  utilitaires chaines — pas de libc donc pas de strlen/strcmp
; str_len  : rdi=chaine -> rax=longueur
; str_eq   : rdi=chaine attendue, compare avec path_buf -> rax=1 si egal
; ------------------------------------------------------------
str_len:
    xor     rax, rax
.loop:
    cmp     byte [rdi + rax], 0
    je      .done
    inc     rax
    jmp     .loop
.done:
    ret

str_eq:
    mov     rsi, path_buf           ; toujours path_buf vs la route attendue
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

; ------------------------------------------------------------
;  Logs : j'affiche chaque requete dans le terminal pour debug
; ------------------------------------------------------------
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

    ; pour POST j'affiche aussi le corps recu (utile pour voir le formulaire)
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

log_rejected_request:
    mov     rax, SYS_WRITE
    mov     rdi, 1
    mov     rsi, log_rejected
    mov     rdx, log_rejected_len
    syscall
    ret

; ------------------------------------------------------------
;  reponse HTTP : header + corps vers le client (fd dans r13)
; r14 = taille du corps, r15b = type MIME (HTML/CSS/JSON/404)
; obligatoire sujet : HTTP/1.1 200 OK + page HTML
; ------------------------------------------------------------
send_body:
    ; choisir le bon header selon le type de contenu
    cmp     r15b, MIME_404
    je      .hdr_404
    cmp     r15b, MIME_CSS
    je      .hdr_css
    cmp     r15b, MIME_PLAIN
    je      .hdr_plain
    mov     rsi, resp_200_hdr
    mov     rdx, resp_200_hdr_len
    jmp     .write_hdr
.hdr_css:
    mov     rsi, resp_200_css_hdr
    mov     rdx, resp_200_css_hdr_len
    jmp     .write_hdr
.hdr_plain:
    mov     rsi, resp_200_plain_hdr
    mov     rdx, resp_200_plain_hdr_len
    jmp     .write_hdr
.hdr_404:
    mov     rsi, resp_404_hdr
    mov     rdx, resp_404_hdr_len
.write_hdr:
    mov     rax, SYS_WRITE
    mov     rdi, r13                ; fd du client (fourni par Noah)
    syscall
.write_body:
    ; 2e write : le contenu (HTML, CSS ou JSON) depuis file_buf
    mov     rax, SYS_WRITE
    mov     rdi, r13
    mov     rsi, file_buf
    mov     rdx, r14
    syscall
    ret

;  bonus sujet : lire un fichier externe depuis le disque
; rdi = chemin ("pages/index.html"), r15b = type MIME
; open -> read dans file_buf -> send_body
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
    mov     rdx, 32768
    syscall
    test    rax, rax
    jle     .close_fail
    mov     rbx, rax

    mov     rax, SYS_CLOSE
    mov     rdi, r14
    syscall

    mov     r14, rbx                ; r14 = nb octets lus (taille du corps)
    call    send_body
    xor     rax, rax                ; 0 = succes
    ret

.close_fail:
    mov     rax, SYS_CLOSE
    mov     rdi, r14
    syscall
.fail:
    mov     rax, -1
    ret

;  bonus : page 404 personnalisee depuis pages/404.html
send_404:
    mov     rdi, file_404
    mov     r15b, MIME_404
    call    serve_file
    ret

;  wrapper : si serve_file echoue (fichier introuvable) -> 404
serve_path:
    call    serve_file
    test    rax, rax
    jnz     send_404
    ret

;  /status : copie le JSON en memoire puis send_body (pas de open)
send_status:
    mov     rdi, file_buf
    mov     rsi, status_body
    mov     rcx, status_body_len
    cld
    rep     movsb
    mov     byte [rdi], 0
    mov     r14, status_body_len
    mov     r15b, MIME_PLAIN
    call    send_body
    ret

; ------------------------------------------------------------
;  routage — bonus routes multiples
; compare path_buf avec chaque route connue via str_eq
; GET : /, /status, /style.css  |  POST : /message
; ------------------------------------------------------------
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
    jmp     serve_path

route_request:
    ; chaine de if/else : path_buf == "/" ? /status ? /style.css ? sinon 404
    mov     rdi, path_root
    call    str_eq
    test    rax, rax
    jnz     .serve_index

    mov     rdi, path_status
    call    str_eq
    test    rax, rax
    jnz     send_status

    mov     rdi, path_css
    call    str_eq
    test    rax, rax
    jnz     .serve_css

    call    send_404
    ret

.serve_index:
    mov     rdi, file_index
    xor     r15b, r15b
    jmp     serve_path

.serve_css:
    mov     rdi, file_css
    mov     r15b, MIME_CSS
    jmp     serve_path

; ------------------------------------------------------------
;  parsing HTTP — obligatoire sujet
; parse_request     : lit GET/POST, remplit path_buf
; parse_content_length / find_body_start / read_post_body : gestion POST
; ------------------------------------------------------------
parse_content_length:
    ; cherche "Content-Length: " dans req_buf et lit le nombre
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

; trouve \r\n\r\n dans les headers = tout ce qui suit = corps POST
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

; assemble le corps POST complet (parfois 2 read si coupe en deux paquets)
read_post_body:
    xor     qword [body_len], 0
    xor     qword [body_ptr], 0

    call    find_body_start
    test    rax, rax
    jz      .done
    mov     rbx, rax

    ; je sauvegarde rbx car parse_content_length l'ecrase
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

    ; si le body est coupe entre deux read, on lit la suite
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

;  coeur du sujet — verifie GET ou POST, extrait le chemin URL
; entree : req_buf rempli par Noah
; sortie : rax=0 si OK, rax=-1 si methode inconnue (-> 405)
; effet  : path_buf = "/status" par exemple
parse_request:
    mov     byte [method_is_post], 0

    ; d'abord on teste GET, sinon on tente POST
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

    ; copie caractere par caractere jusqu'a espace, ? ou fin de ligne
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

; ------------------------------------------------------------
;  Programme principal
;  1) ouvrir le socket et ecouter sur 8080
;  2) boucle infinie : accept -> lire -> traiter -> fermer
; ------------------------------------------------------------
_start:

    ; creation du socket TCP
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
    mov     r13, rax                ; r13 = fd du client connecte

    mov     rax, SYS_READ
    mov     rdi, r13
    mov     rsi, req_buf
    mov     rdx, 4096
    syscall
    test    rax, rax
    jle     .close_conn
    mov     [req_len], rax

    ; =====  couche HTTP — appelee apres le read de Noah =====
    call    parse_request           ; lit methode + chemin dans path_buf
    test    rax, rax
    jnz     .send_405              ; PUT, DELETE... -> header 405

    cmp     byte [method_is_post], 1
    je      .handle_post

    call    log_request             ;  affiche [LOG] GET /...
    call    route_request           ;  choisit et envoie la page
    jmp     .close_conn

.handle_post:
    call    read_post_body          ;  lit le corps du formulaire
    call    log_request
    call    route_post_request      ;  repond a POST /message
    jmp     .close_conn

.send_405:
    call    log_rejected_request
    mov     rax, SYS_WRITE
    mov     rdi, r13
    mov     rsi, resp_405_hdr       ;  header 405 en .data
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
