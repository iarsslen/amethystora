# L’agent IA

`Super+Ctrl+Shift+A` ouvre un agent IA dans un terminal : Claude Code par défaut, ou Opencode si vous
préférez. Il est accompagné d’une compétence qui lui explique ce système : il sait donc quels fichiers
appartiennent à l’image et lesquels vous pouvez modifier, comment fonctionnent les thèmes et les
raccourcis clavier, comment les logiciels s’installent sur un système à base d’image, et ce qu’il doit
vous demander avant de toucher à quoi que ce soit.

Demandez-lui des choses en langage courant :

- « Rends les icônes du dock plus petites. »
- « Pourquoi le ventilateur de mon portable tourne-t-il tout le temps ? »
- « Crée un projet Python avec uv dans ~/code/scraper. »
- « Ajoute un raccourci clavier qui ouvre Mission Center. »
- « Crée un widget pour la barre supérieure qui affiche la météo. » Voir [Widgets](widgets.md).

Il démarre dans son mode normal : il demande donc avant d’exécuter une commande ou de modifier un
fichier. Lisez ce qu’il propose avant d’accepter.

## Diagnostiquer un problème

**Diagnose a problem** dans le menu Amethystora (`Super+Alt+Space`) confie à l’agent quelque chose qui
a mal tourné : un plantage, un service en échec, ou votre propre description (« le Wi-Fi décroche après
la mise en veille »). Il enquête à partir des journaux et des rapports de plantage, ne modifie rien, et
revient avec la cause et une correction proposée.

```bash
amethystora-agent diagnose                       # look for anything that failed recently
amethystora-agent diagnose "wifi drops after suspend"
amethystora-agent diagnose NetworkManager.service
amethystora-agent diagnose 4242                  # a process ID
```

Les applications lui confient ce qui a mal tourné là où vous le voyez : **Demander pourquoi à l’agent**
dans **Mises à jour** quand une mise à jour n’est pas allée au bout, **Demander à l’agent** dans
**Sécurité** à côté de tout ce qui requiert votre attention, et **Demander à l’agent** dans
**Journaux** à côté d’un plantage ou de ce qu’un service a écrit. Elles ne transmettent que le service,
le numéro de processus ou les propres mots du rapport, et l’agent lit le reste lui-même. Tant que les
fonctions d’agent sont désactivées, ces boutons n’apparaissent pas.

## Commandes

| Commande | Rôle |
| --- | --- |
| `amethystora-agent` | Ouvrir l’agent (comme `Super+Ctrl+Shift+A`) |
| `amethystora-agent ask "<question>"` | L’ouvrir avec une première question |
| `amethystora-agent diagnose [...]` | Trouver pourquoi quelque chose est cassé, sans rien modifier |
| `amethystora-agent use claude` ou `use opencode` | Choisir l’agent |
| `amethystora-agent install` | Installer l’agent choisi à l’avance ; aussi `ame agent install` |
| `ame agent toggle` | Désactiver les fonctions d’agent, ou les réactiver |

## Installation et mises à jour

Les agents ne font pas partie de l’image, car ils sortent bien plus souvent qu’elle. La première fois
que vous en ouvrez un, il propose de l’installer dans votre dossier personnel avec l’installateur de
son éditeur. Ensuite, il se met à jour lui-même, quand vous le décidez : `claude update` ou
`opencode upgrade`. Claude Code est installé sur son canal stable, une version sortie il y a environ
une semaine. Comme il vit dans votre dossier personnel, la même copie fonctionne aussi dans n’importe
quelle toolbox ou distrobox.

## Confidentialité et désactivation

Aucun des deux agents ne fait quoi que ce soit tant que vous ne vous y êtes pas connecté, et ce que vous
lui envoyez va au fournisseur auprès duquel vous vous êtes connecté. `ame agent toggle` retire les
entrées de menu, désactive le raccourci clavier et délie la compétence ; un agent que vous avez
installé reste installé dans tous les cas.
