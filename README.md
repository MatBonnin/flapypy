# Flapypy

Un projet de jeux 3D faits avec **Godot 4.6**, parti d'un clone de Flappy Bird
qui a fini en arène de baston roguelite contre des bonhommes-tuyaux. 🐤🥖

## Menu principal (`scenes/menu.tscn`)

C'est la scène lancée par défaut (**F5**). Elle permet de choisir le mode de
jeu :

- **Flappy Bird 3D** — le clone vu de côté (`scenes/main_3d.tscn`) ;
- **Arène solo** — vagues d'ennemis et améliorations roguelite
  (`scenes/arena.tscn`) ;
- **PvP LAN** — multijoueur local 1 à 4 joueurs (`scenes/pvp_arena.tscn`) ;
- **Prop Hunt LAN** — cache-cache déguisé en objets, 2 à 4 joueurs
  (`scenes/prop_hunt.tscn`).

Chaque mode permet de revenir au menu : **Échap** dans le Flappy 3D,
**Pause → Menu principal** dans l'arène (ou **Échap** après un game over), et
le bouton **Menu principal** ou **Quitter vers le menu** côté PvP.

## L'arène solo (`scenes/arena.tscn`)

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

## Prop Hunt LAN (`scenes/prop_hunt.tscn`)

Un cache-cache à la *prop hunt* de Garry's Mod, 2 à 4 joueurs sur le même
réseau. La plaine est chargée d'objets : arbres, rochers, tonneaux, caisses,
bottes de foin, souches, buissons, citrouilles (et la maison en décor).

Déroulé d'une manche :

- l'hôte clique **Héberger**, les autres **Rejoindre**, puis l'hôte clique
  **Lancer la manche** (le rôle de chercheur tourne à chaque manche) ;
- **phase de cachette (12 s)** : le chercheur a un écran noir pendant que les
  props se placent et se déguisent ;
- **phase de chasse (120 s)** : le chercheur traque les props et les élimine à
  la massue (2 coups).

Côté prop : **E** près d'un objet du décor pour prendre exactement son
apparence (un prop déguisé est un peu plus lent), on peut se redéguiser, fuir
et sauter. Côté chercheur : chaque coup de massue dans le vide ou dans un vrai
objet coûte **1 PV** (sur 10) — s'il tombe à 0, les props gagnent. Les props
gagnent aussi si le temps s'écoule avec au moins un survivant ; le chercheur
gagne s'il élimine tout le monde.

La carte est générée avec une graine fixe : tous les joueurs voient exactement
les mêmes objets aux mêmes endroits. L'hôte est autoritaire pour les rôles,
les dégâts et la fin de manche. En fin de manche, retour au lobby et l'hôte
peut relancer sans recharger la scène.

## Le Flappy Bird 3D (`scenes/main_3d.tscn`)

Le jeu d'origine du projet, vu de côté en 3D : **Espace** ou clic pour voler,
**Échap** pour revenir au menu. (La version 2D historique a été supprimée.)

## Lancer le projet

Ouvrir le dossier dans Godot 4.6, puis **F5** (menu principal) ou **F6** sur
une scène précise.

## Tests

Des tests headless simulent des parties pour valider la logique sans ouvrir
l'éditeur :

```sh
godot --headless res://tests/test_arena.tscn      # cycle de vagues + amélioration
godot --headless res://tests/test_boss.tscn       # combat de boss
godot --headless res://tests/test_regen.tscn      # régénération de vie
godot --headless res://tests/test_prop_hunt.tscn  # manche complète de prop hunt
godot --headless res://tests/test_pvp_charge.tscn # charge du lancer de bec en PvP
```

## Sons

Les effets sonores proviennent des packs audio CC0 de
[Kenney](https://kenney.nl) (voir `assets/sounds/LICENSE.txt`).
