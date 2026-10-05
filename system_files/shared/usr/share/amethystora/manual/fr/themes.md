# Thèmes

Un thème est une palette, et tout est peint à partir d’elle. Changez de thème et tout le bureau change
ensemble : le style clair ou sombre et la couleur d’accentuation de GNOME, le terminal, l’invite du
shell, la barre supérieure, le dock, le fond d’écran, VSCodium, et ce manuel. Un thème clair donne au
dock une légère teinte sombre, pour que ses icônes ressortent encore sur un fond d’écran pâle.

## Changer de thème

| Touche | Rôle |
| --- | --- |
| `Super+Ctrl+Shift+Space` | Choisir un thème |
| `Super+Ctrl+D` | Basculer entre les versions claire et sombre du thème |
| `Super+Ctrl+Space` | Fond d’écran suivant du thème actuel |

La même chose depuis un terminal :

```bash
ame desktop theme                   # pick one from a list
amethystora-theme list              # the themes, with the current one marked
amethystora-theme set "Tokyo Night" # apply one by name
amethystora-theme toggle            # light or dark
amethystora-theme current           # which one is on
```

## Les thèmes

| Thème | Nom à utiliser | Style |
| --- | --- | --- |
| Amethystora | `amethystora` | Sombre, par défaut |
| Amethystora Light | `amethystora-light` | Clair |
| Catppuccin Mocha | `catppuccin` | Sombre |
| Catppuccin Latte | `catppuccin-latte` | Clair |
| Everforest | `everforest` | Sombre |
| Gruvbox | `gruvbox` | Sombre |
| Matte Black | `matte-black` | Sombre |
| Nord | `nord` | Sombre |
| Rosé Pine Dawn | `rose-pine-dawn` | Clair |
| Tokyo Night | `tokyo-night` | Sombre |

Les deux thèmes Amethystora apportent aussi le thème GTK Amethystora, celui aux trois voyants colorés
dans le coin de chaque fenêtre. Les autres gardent l’apparence propre à GNOME, dans leur couleur
d’accentuation. `Super+Ctrl+D` fait basculer un thème vers son partenaire (Catppuccin Mocha et Latte,
Amethystora et Amethystora Light) ; un thème sans partenaire bascule vers Amethystora dans l’autre
mode.

## Fonds d’écran

Chaque thème est fourni avec trois fonds d’écran de lieux imaginaires dessinés dans ses propres
couleurs, et passer à un thème met le premier sur le bureau : une ville néon sous la pluie pour Tokyo
Night, une aurore boréale au-dessus d’un lac de montagne pour Nord, des pins dans la brume pour
Everforest, un coucher de soleil sur le désert pour Gruvbox, des sommets sous une lune pastel pour
Catppuccin, une éclipse pour Matte Black, et ainsi de suite. `Super+Ctrl+Space` les fait défiler. Les
deux thèmes Amethystora s’ouvrent sur les facettes d’une pierre taillée, et ont aussi le champ de
cristaux et un ciel nocturne de fumée violette ; les Paramètres de GNOME les proposent sous Apparence.

Pour ajouter les vôtres, placez des images (JPG, PNG, WebP ou SVG) dans un dossier portant le nom du
thème. Elles viennent après les images propres au thème :

```bash
mkdir -p ~/.config/amethystora/backgrounds/amethystora
cp ~/Pictures/mountains.jpg ~/.config/amethystora/backgrounds/amethystora/
```

`amethystora-theme bg list` montre ce que le thème actuel fait défiler, et
`amethystora-theme bg set <picture>` en applique une directement.

## Transitions

Un nouveau thème ou un nouveau fond d’écran n’apparaît pas simplement. L’écran se fige un instant
pendant que tout change en dessous, puis le nouveau bureau s’ouvre en cercle à partir du pointeur, avec
une lueur de la couleur d’accentuation du thème le long du bord. Cela fonctionne de la même façon quelle
que soit la manière dont vous faites le changement : les raccourcis ci-dessus, les Paramètres de GNOME,
ou le bouton Style sombre des réglages rapides.

```bash
ame desktop transition         # pick one from a list
ame desktop transition wave    # or name it
```

| Transition | Aspect |
| --- | --- |
| `grow` | Un cercle s’ouvre à partir du pointeur. Par défaut |
| `outer` | Le nouveau bureau se referme sur le pointeur depuis les bords |
| `wipe` | Un bord adouci balaie l’écran en biais |
| `wave` | La même chose, avec un bord ondulé |
| `fade` | Un simple fondu enchaîné |
| `random` | L’une des quatre premières, sous n’importe quel angle |
| `none` | Aucune animation : le fond d’écran s’estompe comme GNOME le fait |

Une transition dure 1,2 seconde. Pour changer cela, indiquez une durée en millisecondes :

```bash
gsettings set org.gnome.shell.extensions.amethystora-transitions duration 800
```

Il n’y a pas de transitions tant que les animations sont désactivées dans Paramètres, sous
Accessibilité. Elles viennent de l’extension Amethystora Transitions, que le Gestionnaire d’extensions
peut désactiver.

## Icônes

Les icônes sont candy-icons, le même jeu pour tous les thèmes : ses dossiers, ses types de fichiers, et
ses pictogrammes en dégradé pour les applications qui font un travail simple, comme Fichiers,
Paramètres ou la calculatrice. Une application qui a son propre logo le garde. Firefox, Thunderbird, un
IDE JetBrains et la plupart de ce que vous installez affichent l’icône dessinée par leur fabricant, pas
une version redessinée : un logo est une marque, et son apparence relève de son propriétaire. C’est
pourquoi le dock mélange les deux styles.

## Modifier un thème, ou créer le vôtre

Les thèmes sont fournis en lecture seule dans `/usr/share/amethystora/themes`. Un dossier du même nom
dans `~/.config/amethystora/themes` vient s’y superposer : vous n’écrivez donc que les fichiers que vous
voulez changer. Un dossier qui porte un nom à lui est un nouveau thème. Chaque fichier est petit et
facultatif, sauf la palette :

| Fichier | Contient |
| --- | --- |
| `colors.toml` | La palette : `accent`, `foreground`, `background`, `cursor`, `selection_foreground`, `selection_background`, et `color0` à `color15` |
| `light.mode` | Présent, et vide, quand le thème est clair |
| `pair.theme` | Le thème vers lequel bascule `Super+Ctrl+D` |
| `accent.theme` | La couleur d’accentuation de GNOME : blue, teal, green, yellow, orange, red, pink, purple ou slate. Sans lui, la plus proche est choisie |
| `gtk.theme` | Un nom de thème GTK, au lieu de l’apparence propre à GNOME |
| `icons.theme` | Un thème d’icônes, au lieu de candy-icons |
| `cursor.theme` | Un thème de curseur |
| `vscode.theme` | Le thème de couleurs de VSCodium à utiliser |
| `tophat.theme` | La couleur des indicateurs de la barre supérieure, quand l’accentuation passe mal en trait fin |
| `backgrounds/` | Les fonds d’écran |
| `backgrounds.list` | Des fonds d’écran conservés ailleurs sur le système, un chemin par ligne. Le premier est celui sur lequel le thème s’ouvre |

Un thème sans images propres en reçoit quatre dessinées dans ses couleurs : une lueur douce, des
collines dans la brume, une carte en courbes de niveau et des rubans ondoyants.

Un thème à vous tient en trois commandes :

```bash
mkdir -p ~/.config/amethystora/themes/sunset
cp /usr/share/amethystora/themes/amethystora/colors.toml ~/.config/amethystora/themes/sunset/
amethystora-theme set sunset
```

Modifiez les couleurs, relancez `amethystora-theme set sunset`, et regardez le résultat.

## Aller plus loin

- **La façon dont une configuration est écrite.** La palette du terminal, l’invite, les couleurs de
  btop et les fonds d’écran dessinés sont des modèles situés dans `/usr/share/amethystora/themed`.
  Copiez-en un dans `~/.config/amethystora/themed/` et modifiez la copie pour changer la façon dont
  chaque thème le rend.
- **Lancer quelque chose à chaque changement.** Placez un exécutable dans
  `~/.config/amethystora/hooks/theme-set.d/`. Il reçoit le nom du thème dans `AMETHYSTORA_THEME` et son
  dossier dans `AMETHYSTORA_THEME_DIR`.
- **Votre propre invite reste la vôtre.** Si vous avez écrit vous-même `~/.config/starship.toml`, le
  thème n’y touche pas.
- **Ne modifiez jamais `~/.config/amethystora/current/`.** Il est réécrit à chaque changement.

## Le menu de démarrage

Le menu de démarrage peut aussi porter les illustrations d’Amethystora. C’est désactivé par défaut,
car le menu de démarrage se trouve hors de l’image :

```bash
ame desktop boot-menu
```

Relancez la commande pour retirer les illustrations. Une fois activées, les mises à jour de l’image les
tiennent à jour.
