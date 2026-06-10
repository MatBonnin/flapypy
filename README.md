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

## MVP PvP LAN (`scenes/pvp_arena.tscn`)

Mode multijoueur local 1 a 4 joueurs sur le meme reseau :

- un joueur clique **Heberger** ;
- les autres lancent la meme scene, entrent l'IP locale de l'hote, puis cliquent
  **Rejoindre** ;
- la manche dure 120 secondes ;
- l'hote est autoritaire pour les degats, les morts, le score et la fin de
  manche ;
- le MVP synchronise les positions, les PV, les morts, les coups de massue, les
  lancers de bec et le classement.
- le PvP est maintenant en deathmatch : un joueur KO revient apres quelques
  secondes, et le vainqueur est celui qui a le plus d'eliminations au timer.
- des bonus apparaissent dans l'arene : coeur, baguette, bec d'or, cafe et
  champignon.
- l'hote peut relancer une manche avec **Entree** a l'ecran de victoire.
- les touches sont configurables depuis **Parametres des touches** dans le menu
  PvP, ou avec **Echap** pendant la partie.

Limitations actuelles du MVP : pas encore de lobby avance, pas de relance sans
vote cote clients, et la connexion reste limitee au LAN direct par IP.

### Depannage LAN

Le PvP utilise ENet en UDP sur le port **42424**.

- L'hote doit donner une IPv4 locale affichee dans le menu PvP, par exemple
  `192.168.1.23` ou `10.0.0.12`. Ne pas donner `127.0.0.1` : cette adresse
  pointe toujours vers le PC du joueur lui-meme.
- Les deux PC doivent etre sur le meme reseau local. Si Windows marque le Wi-Fi
  en reseau public, passer le reseau en prive peut etre necessaire.
- Au premier lancement, Windows Defender peut bloquer l'EXE. Sur le PC hote,
  autoriser `Flapypy_PvP.exe` sur les reseaux prives, ou ajouter une regle
  entrante UDP pour le port `42424`.
- Pour exporter directement le PvP, verifier que la scene principale du projet
  est `res://scenes/pvp_arena.tscn` avant de refaire l'EXE.

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
