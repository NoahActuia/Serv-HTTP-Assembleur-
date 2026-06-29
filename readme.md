; http_server.asm  —  Serveur HTTP minimal
; NASM x86-64, Linux — Port d'écoute : 8080
;
; Compilation :
;   nasm -f elf64 http_server.asm -o http_server.o
;   ld -o http_server http_server.o
;
; Lancement :
;   ./http_server
;
; Test :
;   curl http://localhost:8080
;   Ou ouvrir http://localhost:8080 dans un navigateur# Serv-HTTP-Assembleur-
# Serv-HTTP-Assembleur-
