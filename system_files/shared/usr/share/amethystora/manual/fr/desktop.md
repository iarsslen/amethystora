# Se repérer

Le bureau est GNOME, organisé pour le clavier. Tout ce qui suit fonctionne aussi à la souris, mais une
fois les raccourcis dans les doigts, vous la toucherez rarement.

## La barre supérieure

- **À gauche**, les six espaces de travail. Celui sur lequel vous êtes est mis en évidence ; cliquez
  sur un autre pour y aller.
- **Au milieu**, l’horloge. Cliquez dessus, ou appuyez sur `Super+V`, pour les notifications et
  l’agenda.
- **À droite**, les indicateurs de processeur, de mémoire et de réseau, puis le menu système : Wi-Fi,
  son, alimentation et le reste des réglages rapides.

Les indicateurs et les espaces de travail suivent les couleurs du [thème](themes.md) actuel. La barre
peut aussi afficher vos propres [widgets](widgets.md), que l’agent IA crée pour vous.

## Trouver des choses

- `Super+Space` recherche des applications, des fichiers et des paramètres, et lance ce que vous
  choisissez.
- `Super` seul ouvre la vue d’ensemble : toutes les fenêtres ouvertes d’un coup, avec la recherche en
  haut.
- `Super+A` affiche toutes les applications installées.

Les deux recherches pardonnent les fautes de frappe dans les noms d’applications : `calxu` trouve
quand même Calculatrice.

## Le presse-papiers

`Super+Shift+V` ouvre l’historique du presse-papiers : les 15 derniers éléments copiés. Choisissez-en
un pour le copier de nouveau, tapez pour rechercher, et épinglez ceux auxquels vous revenez souvent.
On le trouve aussi sous l’icône de presse-papiers de la barre supérieure.

L’historique ne dure que le temps de votre session, et seuls les éléments épinglés sont enregistrés.
Avant de copier quelque chose de secret, activez **Mode privé** dans le même menu : plus rien n’est
enregistré jusqu’à ce que vous le désactiviez.

## Le dock

Le dock, en bas, contient vos applications épinglées et celles en cours d’exécution. `Alt+1` à
`Alt+9` basculent vers l’application de cet emplacement, et l’ouvrent si elle n’est pas lancée.
Faites un clic droit sur une application pour l’épingler ou la désépingler.

## Le menu Amethystora

`Super+Alt+Space` ouvre un seul menu pour ce qui est sinon dispersé entre Paramètres, le terminal et
[`ame`](terminal.md#ame) :

| Entrée | Rôle |
| --- | --- |
| Ask an agent | Ouvre l’[agent IA](ai-agent.md) |
| Diagnose a problem | Demande à l’agent de trouver pourquoi quelque chose est cassé |
| Make a widget | Demande à l’agent de créer un [widget](widgets.md) pour la barre supérieure |
| Theme | Le sélecteur de thème |
| Background | Les fonds d’écran du thème actuel |
| Keybindings | Les raccourcis clavier, dans le terminal |
| Manual | Ce manuel |
| Web apps | Installer ou supprimer une [application web](web-apps.md) |
| Apps and system commands | Toutes les commandes `ame`, chacune dans son groupe |
| System | Verrouiller, se déconnecter, redémarrer, éteindre, rechercher des mises à jour, le rapport de sécurité |

Déplacez-vous avec les flèches ou tapez pour filtrer, `Enter` pour choisir, `Esc` pour revenir.

## Fenêtres en mosaïque

PaperWM range les fenêtres pour vous. Chaque espace de travail est une bande de fenêtres placées côte
à côte sur toute la hauteur, et la bande peut être plus large que l’écran. Une nouvelle fenêtre s’ouvre
à droite de celle où vous êtes, les fenêtres ne se chevauchent jamais, et la bande défile pour garder
la fenêtre active visible :

```
  ┌────────┬──────────────┬──────────────────────┬────────┐
  │  Mail  │   Terminal   │       Browser        │  Chat  │
  └────────┴──────────────┴──────────────────────┴────────┘
           ╰──────────── the screen ─────────────╯
```

Mail et Chat sont toujours ouverts, juste au-delà du bord. `Super+Left` revient à Mail. Poussez le
pointeur contre le bord gauche ou droit de l’écran pour voir ce qu’il y a au-delà, et cliquez sur une
fenêtre pour y aller. Sur un pavé tactile, balayez avec trois doigts pour faire glisser la bande.

Les raccourcis suivent une même logique. `Super` et une flèche passe à une autre fenêtre. Ajoutez
`Ctrl` et c’est la fenêtre qui se déplace. Ajoutez `Shift` et vous passez à un autre écran.

### Se déplacer

| Touche | Rôle |
| --- | --- |
| `Super+Left` / `Super+Right` | La fenêtre à gauche / à droite |
| `Super+Up` / `Super+Down` | La fenêtre au-dessus / en dessous, quand des fenêtres partagent une colonne |
| `Super+Home` / `Super+End` | La première / dernière fenêtre de l’espace de travail |
| `Super+[` / `Super+]` | Faire glisser la bande sans changer de fenêtre active |
| `Super+Shift` et une flèche | L’écran dans cette direction |

### Disposer

| Touche | Rôle |
| --- | --- |
| `Super+Ctrl+Left` / `Super+Ctrl+Right` | Déplacer la fenêtre vers la gauche / la droite le long de la bande |
| `Super+Ctrl+Up` / `Super+Ctrl+Down` | La déplacer vers le haut / le bas dans sa colonne |
| `Super+I` | Faire entrer la fenêtre de droite dans cette colonne, sous celle-ci |
| `Super+O` | Sortir la fenêtre du bas de cette colonne dans une colonne à part |
| `Super+Shift+O` | Sortir cette fenêtre dans une colonne à part |
| `Super+Ctrl+Page Up` / `Page Down` | La déplacer vers l’espace de travail précédent / suivant |
| `Super+Shift+Ctrl` et une flèche | La déplacer vers l’écran dans cette direction |
| `Super+T`, en maintenant `Super` | Emporter la fenêtre pendant que vous vous déplacez, et la déposer là où vous relâchez |

### Dimensionner

| Touche | Rôle |
| --- | --- |
| `Super+R` | Faire passer la largeur par 38 %, 50 % et 62 % de l’écran (`Super+Alt+R` revient en arrière) |
| `Super+Shift+R` | La même chose pour la hauteur d’une fenêtre dans une colonne |
| `Super+F` | Occuper toute la largeur de l’écran, et revenir |
| `Super+C` | Centrer la fenêtre à l’écran |
| `Super+Shift+C` | Où la bande amène une fenêtre active : juste dans le champ, au centre ou au bord |
| `Super+Shift+W` | Où s’ouvrent les nouvelles fenêtres : à droite, à gauche ou sous celle-ci |

### Fenêtres flottantes

Les boîtes de dialogue flottent d’elles-mêmes au-dessus de la bande. `Super+Ctrl+Escape` sort la
fenêtre active de la bande pour qu’elle flotte aussi, et l’y remet. `Super+Alt+Escape` masque d’un coup
toutes les fenêtres rendues flottantes de cette façon, et les fait réapparaître.

### Et le reste

| Touche | Rôle |
| --- | --- |
| `Super+N` | Une nouvelle fenêtre de l’application en cours |
| `Super+Ctrl+B` | Masquer ou afficher la barre supérieure sur cet espace de travail |

Les paramètres de PaperWM se trouvent sous **PaperWM** dans le **Gestionnaire d’extensions**. On y
trouve les espacements, les largeurs que parcourt `Super+R`, et tous les raccourcis, dont certains que
cette page ne mentionne pas.

### Fenêtres classiques

Si vous préférez des fenêtres qui flottent et se chevauchent, comme sous Windows et macOS, passez à la
disposition classique :

```bash
ame desktop layout classic
```

Elle désactive PaperWM, et les mises à jour le laissent désactivé. Les fenêtres s’ouvrent alors là où
GNOME les place, et vous les déplacez par leur barre de titre. `Super+Up` maximise et `Super+Down`
restaure, `Super+Left` / `Super+Right` placent une fenêtre sur cette moitié de l’écran, et
`Super+Shift+Left` / `Super+Shift+Right` la déplacent vers l’écran suivant. `ame desktop layout tiling`
rétablit la bande. La première fois que vous vous connectez, une notification propose le même choix.

## Fenêtres

| Touche | Rôle |
| --- | --- |
| `Super+W` | Fermer la fenêtre |
| `Super+Backspace` | Redimensionner avec les flèches |
| `Shift+F11` | Plein écran, en gardant la barre de titre |
| `Super+Tab` / `Alt+Tab` | Passer d’une application à l’autre / d’une fenêtre à l’autre |

Les boutons à droite de chaque barre de titre réduisent, maximisent et ferment la fenêtre.

## Espaces de travail

Il y en a toujours six, donc `Super+3` désigne toujours le même endroit. Une façon courante de les
utiliser : un navigateur sur le 1, un terminal sur le 2, la messagerie sur le 6. `Super+Shift+3` emmène
la fenêtre active sur l’espace de travail 3. `Super+Page Up` / `Super+Page Down` passent à l’espace de
travail précédent / suivant, et `Super+Shift+Ctrl+Left` / `Super+Shift+Ctrl+Right` déplacent la
fenêtre vers l’écran suivant.

## Extensions

Ces extensions de GNOME Shell sont fournies avec l’image :

| Extension | Ce qu’elle fait |
| --- | --- |
| PaperWM | La [mosaïque](#tiling-windows) : les fenêtres côte à côte sur une bande qui défile |
| Space Bar | Les espaces de travail dans la barre supérieure |
| TopHat | Les indicateurs de processeur, de mémoire et de réseau |
| Dash to Dock | Le dock |
| Search Light | La recherche sur `Super+Space` |
| Fuzzy App Search | Une recherche d’applications qui pardonne les fautes de frappe |
| Clipboard Indicator | L’[historique du presse-papiers](#the-clipboard) sur `Super+Shift+V` |
| Blur my Shell | Le verre dépoli derrière le panneau, la vue d’ensemble et les fenêtres |
| Just Perfection | Des animations plus rapides, et pas de fenêtre surgissante quand vous changez d’espace de travail |
| AppIndicator | Les icônes de la zone de notification pour les applications qui en utilisent |
| Caffeine | Un interrupteur dans les réglages rapides qui garde l’écran allumé |
| GSConnect | Votre téléphone Android : notifications, fichiers, presse-papiers, SMS |
| Logo Menu | Le logo Amethystora en haut à gauche : des raccourcis vers les outils système |
| Gradia | Annoter une capture d’écran juste après l’avoir prise |
| Bazaar integration | Relie le shell à Bazaar, la logithèque |

Désactivez n’importe laquelle, ou modifiez ses paramètres, dans le **Gestionnaire d’extensions**. Une
chose à savoir : après chaque mise à jour de l’image, les extensions propres à l’image sont réactivées,
pour qu’une extension désactivée par accident, ou par un plantage, ne le reste pas définitivement. Une
désactivation dure jusqu’à la mise à jour suivante. L’exception est PaperWM avec la
[disposition classique](#classic-windows), qui reste désactivé.

## Fichiers

`Super+Shift+F` ouvre une fenêtre de Fichiers et `Super+E` votre dossier personnel. Les dossiers
s’ouvrent en grille, où les dossiers du thème d’icônes apparaissent sous la forme de leurs
illustrations.
