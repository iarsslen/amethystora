# Widgets

La barre supérieure peut afficher des choses à vous : un minuteur de concentration, la météo, les
courriels non lus, l’état du VPN, le nombre de pull requests qui attendent votre relecture. Chacune est
un *widget*, un petit programme dont la barre transforme la sortie en un libellé, une icône et un menu.
Vous n’avez pas à l’écrire vous-même : l’[agent IA](ai-agent.md) s’en charge.

## Demander un widget à l’agent

Choisissez **Make a widget** dans le menu Amethystora (`Super+Alt+Space`) et dites ce qu’il doit
afficher, ou exécutez :

```bash
amethystora-widgets make "a pomodoro timer"
amethystora-widgets make "how many pull requests wait for my review on GitHub"
amethystora-widgets make                          # the agent asks you what you want
```

L’agent écrit le widget, le vérifie, et celui-ci apparaît dans la barre dès qu’il est enregistré, sans
avoir à vous déconnecter. Demandez des modifications de la même façon : « fais aussi afficher demain
au widget météo ».

Quand un widget cesse de fonctionner, la barre affiche un panneau d’avertissement à sa place. Cliquez
dessus pour lire ce qui s’est mal passé ; **Fix it with the AI agent** confie le problème à l’agent.

## Commandes

| Commande | Rôle |
| --- | --- |
| `amethystora-widgets` | Liste vos widgets, et ceux qui sont activés |
| `amethystora-widgets make ["<idea>"]` | Demande à l’agent d’en créer un |
| `amethystora-widgets new <name> [<example>]` | En commence un à partir d’un exemple : `hello`, `pomodoro` ou `do-not-disturb` |
| `amethystora-widgets run <name>` | L’exécute une fois comme le fait la barre, et dit ce qui ne va pas |
| `amethystora-widgets fix <name> ["<what is wrong>"]` | Demande à l’agent de trouver pourquoi il échoue, et de le corriger |
| `amethystora-widgets off <name>` et `on <name>` | Le masque de la barre, ou l’affiche de nouveau |
| `amethystora-widgets remove <name>` | Le met à la corbeille |
| `amethystora-widgets restart` | Arrête et redémarre tous les widgets |

`ame desktop widgets` exécute les mêmes commandes.

## En créer un vous-même

Un widget est un dossier dans `~/.config/amethystora/widgets`, contenant un `widget.json` qui nomme une
commande et indique à quelle fréquence l’exécuter, et la commande elle-même, généralement un court
script. Le script affiche une ligne que la barre montre : du texte brut, ou du JSON avec une icône, une
couleur du thème et un menu dont les éléments exécutent des commandes, ouvrent des liens ou actionnent
des interrupteurs.

`amethystora-widgets new mywidget` copie l’exemple `hello` en place comme point de départ, et
`amethystora-widgets run mywidget` le vérifie après chaque modification. Le format complet est décrit
dans le guide de l’agent lui-même, `/usr/share/amethystora/agents/skills/amethystora-widgets/SKILL.md` ;
les exemples sont dans `/usr/share/amethystora/widgets/examples`.

## Sécurité

Un widget s’exécute en votre nom, avec accès à vos fichiers, comme tout programme que vous lancez. Ne
gardez que les widgets que vous avez lus ou demandés à l’agent, et lisez ce que l’agent propose avant
d’accepter, puisqu’il demande avant d’écrire quoi que ce soit.

Les widgets s’exécutent hors de GNOME Shell : un widget cassé ou lent affiche donc un panneau
d’avertissement au lieu de figer le bureau ou de mettre fin à votre session. Ils s’arrêtent pendant que
l’écran est verrouillé.
