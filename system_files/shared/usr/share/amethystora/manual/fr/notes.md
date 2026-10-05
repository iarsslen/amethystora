# Notes et tâches

**Notes**, dans la grille d’applications, garde vos notes et vos listes de tâches dans une seule
fenêtre. Tout reste sur cet ordinateur. Rien n’est synchronisé, et l’application ne se connecte jamais
à Internet. Elle remplace Joplin et Planify, et reprend ce que vous y avez déjà (voir
[Vous venez de Joplin ou de Planify](#coming-from-joplin-or-planify)).

La première fois que vous l’ouvrez, elle propose de chiffrer vos notes avec une phrase de passe. C’est
le choix qu’elle recommande, et le reste de cette page suppose que vous l’avez fait.

## Notes

Les notes s’écrivent en Markdown et sont rangées dans des carnets, qui peuvent contenir d’autres
carnets. L’éditeur montre le texte et la note mise en forme côte à côte. **Ctrl+E** bascule entre le
texte, les deux, et la note mise en forme seule.

- **Listes de cases à cocher :** `- [ ] like this`. Cochez les cases dans la note mise en forme.
- **Pièces jointes :** collez une image, déposez un fichier sur la note, ou utilisez le trombone. Les
  images s’affichent dans la note. Cliquez sur toute autre pièce jointe pour en enregistrer une copie.
- **Étiquettes :** tapez dans la ligne d’étiquettes sous le titre et appuyez sur **Entrée**. Les
  étiquettes sont listées dans la barre latérale.
- **Déplacer une note :** choisissez un autre carnet en haut de la note, ou faites glisser la note sur
  un carnet de la barre latérale.
- **Versions précédentes :** l’horloge en haut d’une note. Une version est conservée chaque fois que
  vous revenez modifier une note après dix minutes sans y toucher, jusqu’aux 30 dernières. En restaurer
  une conserve aussi comme version le texte qu’elle remplace.
- **Corbeille :** une note que vous supprimez va à la corbeille, où vous pouvez la restaurer ou la
  supprimer définitivement.
- **PDF :** le menu **⋯** d’une note l’exporte en PDF.

## Tâches

**Tâches**, en haut de la barre latérale, bascule vers vos listes de tâches :

| Vue | Affiche |
| --- | --- |
| Boîte de réception | Les tâches qui ne sont dans aucun projet |
| Aujourd’hui | Ce qui est prévu aujourd’hui, et tout ce qui est en retard |
| À venir | La semaine à venir, jour par jour, et tout ce qui suit |
| Épinglées | Les tâches que vous avez épinglées |
| Terminées | Ce que vous avez terminé, le plus récent d’abord |

Les projets regroupent les tâches et peuvent être divisés en sections. Les libellés traversent les
projets. Cliquez sur une tâche pour régler sa date et son heure, sa répétition, son rappel, sa
priorité, ses libellés et ses notes, et pour ajouter des sous-tâches.

Le champ **Ajouter une tâche** comprend quelques mots d’anglais courant. Il retire ces éléments du
titre :

| Tapez | Pour |
| --- | --- |
| `today`, `tomorrow`, `friday`, `next week`, `2026-10-31` | La date |
| `5pm`, `17:30` | L’heure, avec un rappel à cette heure-là |
| `every day`, `every 2 weeks`, `monthly` | Une tâche qui se répète |
| `p1` à `p4` | La priorité, `p1` étant la plus haute |
| `@errand` | Un libellé, créé s’il est nouveau |
| `#Garden` | Un projet existant |

Terminer une tâche qui se répète la reporte à sa date suivante.

### Rappels

Une tâche avec une heure peut vous faire un rappel, de **À l’heure prévue** à **1 jour avant**. Les
rappels apparaissent sous forme de notifications tant que Notes est ouvert. Quand vous fermez la
fenêtre, Notes reste ouvert en arrière-plan jusqu’à ce que les rappels à venir se soient déclenchés.
Vous pouvez désactiver cela dans **Paramètres**. Vos notes sont verrouillées pendant ce
fonctionnement ; seuls les titres et les heures des rappels sont conservés, en mémoire.

## Chiffrement

Quand le chiffrement est activé, vos notes, tâches et pièces jointes sont écrites sur le disque
chiffrées avec AES-256-GCM, sous une clé aléatoire que seule votre phrase de passe, ou une
[clé d’accès](#passkeys) que vous ajoutez, peut ouvrir. La phrase de passe est renforcée avec scrypt,
qui coûte 128 Mio de mémoire par essai : essayer des phrases de passe l’une après l’autre est donc
lent.

Il reste sûr face aux ordinateurs quantiques. Ce qu’un ordinateur quantique casse, c’est la
cryptographie à clé publique (RSA, courbes elliptiques), et il n’y en a aucune ici. Face à un
chiffrement comme AES, le mieux qu’un ordinateur quantique puisse faire est de diviser par deux la
longueur de la clé. AES-256 garde donc une robustesse de 128 bits, et c’est pourquoi AES-256 est ce que
le NIST et la CNSA 2.0 de la NSA retiennent pour l’ère des ordinateurs quantiques.

> **Personne ne peut retrouver une phrase de passe oubliée.** Ni Amethystora, ni un administrateur,
> ni qui que ce soit. Conservez-la en lieu sûr, et gardez une [sauvegarde](#backing-up).

Vos notes se verrouillent :

- après 10 minutes sans utiliser Notes (**Paramètres**, **Verrouiller en votre absence**),
- quand l’écran se verrouille, que l’ordinateur se met en veille ou que la fenêtre se ferme,
- quand vous appuyez sur **Ctrl+L** ou sur **Verrouiller** dans la barre latérale.

**Paramètres** permet aussi de changer la phrase de passe, et de désactiver ou de réactiver le
chiffrement.

### Clés d’accès

Une clé de sécurité FIDO2 (YubiKey, Thetis, ou un modèle à empreinte digitale comme la YubiKey Bio)
peut ouvrir vos notes, pour que vous n’ayez pas à saisir la phrase de passe à chaque fois. La phrase de
passe continue de fonctionner, et c’est elle qui ouvre vos notes si la clé est perdue : une clé d’accès
est une seconde porte d’entrée, jamais la seule.

Pour en ajouter une, branchez la clé, ouvrez **Paramètres** et choisissez **Ajouter une clé d’accès**.
Saisissez votre phrase de passe et le code PIN de la clé, ou laissez le code PIN vide pour une clé qui
lit votre empreinte digitale. La clé clignote deux fois ; touchez-la à chaque fois. Dès lors, l’écran de
verrouillage propose **Ouvrir avec une clé d’accès**, qui demande le code PIN de la clé, ou votre
empreinte digitale, et un contact.

- **La clé a besoin d’un code PIN**, et un modèle à empreinte digitale d’un doigt enregistré.
  Définissez-les dans Firefox à l’adresse `about:webauthn`. Un simple contact n’ouvre jamais vos
  notes : quelqu’un qui trouve la clé ne peut pas l’utiliser sans le code PIN ou votre doigt, et la clé
  bloque son code PIN après huit essais erronés.
- **Ajoutez une deuxième clé en secours**, une à la fois. Chacune est listée dans **Paramètres**, où
  **Retirer** l’empêche d’ouvrir vos notes.
- **Si une clé est perdue**, retirez-la. Quelqu’un qui détient la clé, connaît son code PIN et possède
  une ancienne copie de votre dossier de notes pourrait encore ouvrir cette copie. Désactiver puis
  réactiver le chiffrement donne une nouvelle clé à vos notes, qu’aucune clé d’accès retirée n’ouvre ;
  ajoutez ensuite de nouveau les clés que vous avez encore.
- Une [sauvegarde](#backing-up) demande toujours la phrase de passe : les clés d’accès n’en font pas
  partie.

La clé ne garde rien de vos notes. Elle détient un secret qui ne la quitte jamais et, une fois le code
PIN ou l’empreinte vérifiés, elle calcule une valeur (HMAC-SHA256, le `hmac-secret` de FIDO2) sous
laquelle est chiffrée une seconde copie de la clé de vos notes. Ce qui est sur le disque reste chiffré
avec AES-256 uniquement.

## Sauvegarder

Comme rien n’est synchronisé, gardez une copie ailleurs. Dans **Paramètres** :

- **Sauvegarder dans un fichier** écrit un seul fichier `.amnotes` qui contient tout, pièces jointes
  comprises, chiffré comme vos notes. Il s’ouvre avec la phrase de passe que vous aviez au moment de sa
  création, sur n’importe quel ordinateur : choisissez-le sous **Importer**.
- **Exporter en Markdown** écrit chaque note dans un fichier Markdown, avec un dossier par carnet, et
  chaque projet sous forme de liste de cases à cocher. Ces fichiers ne sont **pas** chiffrés.

Vos notes elles-mêmes se trouvent dans `~/.local/share/amethystora-notes`.

## Vous venez de Joplin ou de Planify

Ouvrez **Paramètres** et utilisez **Importer**. Importer de nouveau le même fichier met à jour ce qui en
provient au lieu de l’ajouter deux fois.

- **Joplin :** dans Joplin, choisissez **Fichier**, **Tout exporter**, **JEX**. Importez le fichier
  `.jex`. Carnets, notes, étiquettes et pièces jointes sont repris. Les tâches de Joplin deviennent des
  tâches dans la boîte de réception.
- **Planify :** dans Planify, ouvrez **Préférences**, **Sauvegardes**, et créez une sauvegarde. Importez
  son fichier `.json` depuis
  `~/.var/app/io.github.alainm23.planify/data/io.github.alainm23.planify/backups`. Projets, sections,
  tâches, sous-tâches, libellés, dates et répétitions sont repris.
- Les **fichiers Markdown** vont dans un carnet nommé **Imported**.

Une fois tout repris, vous pouvez supprimer les anciennes applications dans Bazaar, ou avec
`flatpak uninstall net.cozic.joplin_desktop io.github.alainm23.planify`.

## Raccourcis

| Touche | Rôle |
| --- | --- |
| **Ctrl+N** | Une nouvelle note, ou une nouvelle tâche dans **Tâches** |
| **Ctrl+F** | Rechercher dans les notes ou les tâches |
| **Ctrl+1** / **Ctrl+2** | Notes / Tâches |
| **Ctrl+E** | Le texte, les deux, ou la note mise en forme |
| **Ctrl+B**, **Ctrl+I**, **Ctrl+K** | Gras, italique, lien |
| **Ctrl+L** | Verrouiller |
| **Ctrl+,** | Paramètres |
