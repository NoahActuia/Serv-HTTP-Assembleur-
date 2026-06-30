# Serv-HTTP-Assembleur

Serveur HTTP ecrit en **assembleur NASM x86-64** pour Linux.  
Aucune libc, aucun framework — uniquement des syscalls.

Le site servi sur le port **8080** contient aussi la **presentation du projet** (menu en haut de la page).

---

## Prerequis

- Linux x86-64
- [NASM](https://www.nasm.us/)
- `ld` (binutils)
- `make`
- `curl` (pour tester, optionnel)

```bash
sudo apt install nasm make curl
```

---

## Lancer le projet

```bash
# Compiler
make

# Demarrer le serveur
./http_server
```

Le terminal affiche :

```
Serveur HTTP demarre sur le port 8080...
```

Ouvrir dans un navigateur : **http://localhost:8080**

Pour arreter le serveur : `Ctrl+C`

---

## Tester

### Navigateur

Aller sur `http://localhost:8080` et naviguer dans la presentation via le menu.

### curl

```bash
curl http://localhost:8080/
curl http://localhost:8080/status
curl http://localhost:8080/style.css
curl -d "msg=Hello" http://localhost:8080/message
```

---

## Routes disponibles

| Methode | Route        | Description                    |
|---------|--------------|--------------------------------|
| GET     | `/`          | Presentation + pages HTML      |
| GET     | `/status`    | Etat du serveur (JSON)         |
| GET     | `/style.css` | Feuille de style               |
| POST    | `/message`   | Formulaire de demo             |
| *       | autre        | Page 404                       |

---

## Structure du projet

```
Serv-HTTP-Assembleur/
├── http_server.asm    # Code source du serveur
├── Makefile           # Compilation
├── pages/
│   ├── index.html     # Presentation integree
│   ├── style.css      # Styles
│   ├── 404.html       # Page d'erreur
│   └── post_ok.html   # Confirmation POST
└── readme.md
```

---

## Presentation integree

La page d'accueil (`/`) sert de support de presentation. Sections accessibles via le menu :

| Slide | Section      | Sujet                        |
|-------|--------------|------------------------------|
| 01    | `#intro`     | Introduction                 |
| 02    | `#socket`    | Ouverture du socket          |
| 03    | `#boucle`    | Boucle accept / read         |
| 04    | `#parsing`   | Parsing GET / POST           |
| 05    | `#routage`   | Routage des URLs             |
| 06    | `#reponse`   | Envoi de la reponse HTTP     |
| 07    | `#bonus`     | Fonctionnalites bonus        |
| 08    | `#demo`      | Demo live + conclusion       |

---

## Depannage

**`Address already in use`** — un serveur tourne deja sur le port 8080 :

```bash
pkill http_server
./http_server
```

**Recompiler proprement** apres une modification :

```bash
make clean && make
```
