# Flapypy

Un projet de jeux 3D faits avec **Godot 4.6**, parti d'un clone de Flappy Bird
qui a fini en arène de baston roguelite contre des bonhommes-tuyaux. 🐤🥖

## Le jeu principal : l'arène (`scenes/arena.tscn`)

Un oiseau Flappy avec bras, jambes et massue affronte des vagues de
bonhommes-tuyaux dans une petite plaine (murs, arbres, rochers, maison).

### Commandes

| Touche | Action |
| --- | --- |
| **ZQSD / Flèches** | Se déplacer |
| **E** | Coup de massue |
| **F** | Lancer son bec comme projectile |
| **Espace** | Sauter (esquive les attaques au sol) |
| **Échap** | Pause et paramètres des touches |
| **1 / 2 / 3** | Choisir une amélioration entre deux vagues |
| **Entrée** | Rejouer après un game over |

Les touches de l'arène sont configurables depuis **Pause → Paramètres**. Les
changements sont sauvegardés localement.

### Contenu

- **Système de vagues** annoncées, de plus en plus grosses, avec choix d'une
  amélioration parmi trois après chaque vague nettoyée (roguelite).
- **5 types d'ennemis** : normal, coureur rapide, tank costaud, cracheur à
  distance, et **LE TUYAU SUPRÊME** (boss toutes les 5 vagues, avec barre de vie).
- **Bonus lâchés par les ennemis** : cœur (+PV), baguette magique, bec d'or
  (triple tir), café (vitesse), champignon (mode géant).
- **Game feel** : tremblement de caméra, hit-stop, flash de dégâts, particules,
  sons à hauteur variable.

## Les jeux d'origine

- `scenes/main.tscn` — le Flappy Bird **2D** classique.
- `scenes/main_3d.tscn` — la version **3D** vue de côté.

Ces deux scènes sont en format portrait (480×800) ; l'arène est en paysage PC.
Pour changer le jeu lancé par défaut : *Projet → Paramètres → Application → Run →
Main Scene*.

## Lancer le projet

Ouvrir le dossier dans Godot 4.6, puis **F5** (scène principale) ou **F6** sur
une scène précise.

## Tests

Des tests headless simulent des parties pour valider la logique sans ouvrir
l'éditeur :

```sh
godot --headless res://tests/test_arena.tscn   # cycle de vagues + amélioration
godot --headless res://tests/test_boss.tscn     # combat de boss
```
