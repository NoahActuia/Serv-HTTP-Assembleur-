# Serv-HTTP-Assembleur

Serveur HTTP en **NASM x86-64** — syscalls Linux, sans libc.

La **presentation du projet** est integree directement dans le site : ouvrez `http://localhost:8080` et naviguez avec le menu en haut.

## Compilation & lancement

```bash
make
./http_server
```

## Sections de la presentation (menu en haut)

| Ancre | Contenu |
|-------|---------|
| `#intro` | Titre et introduction |
| `#objectifs` | Objectifs du sujet |
| `#architecture` | Schema reseau + HTTP |
| `#obligatoire` | Fonctionnalites obligatoires |
| `#bonus` | Bonus realises |
| `#demo` | Tests curl + formulaire POST |
| `#binome` | Repartition du travail |
| `#conclusion` | Conclusion |

## Routes serveur

| Methode | Route | Description |
|---------|-------|-------------|
| GET | `/` | Presentation complete |
| GET | `/status` | API JSON |
| GET | `/style.css` | Feuille de style |
| POST | `/message` | Demo formulaire |
| * | autre | 404 |

## Tests

```bash
curl http://localhost:8080/
curl http://localhost:8080/status
curl -d "msg=test" http://localhost:8080/message
```
