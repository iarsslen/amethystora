# Applications web

Bon nombre des applications que vous utilisez sont des sites web : la messagerie, la discussion, la
musique, un agenda. Une application web en place un dans sa propre fenêtre, sans onglets ni barre
d’adresse, avec sa propre icône dans la grille d’applications et le dock, et sa propre place dans
`Alt+Tab`.

## En installer une

Dans le menu Amethystora (`Super+Alt+Space`), choisissez **Web apps**, puis **Install a web app**, et
répondez à trois questions : un nom, l’adresse et une icône. Laissez l’icône vide et celle du site est
récupérée. La même chose depuis un terminal :

```bash
amethystora-webapp install "Proton Mail" mail.proton.me
amethystora-webapp install "Calendar" https://calendar.proton.me ~/Pictures/calendar.png
```

L’icône peut être une image sur le Web, un fichier, ou le nom d’une icône du thème d’icônes.

## Ouvrir, épingler, supprimer

Une application web se trouve dans la grille d’applications comme n’importe quelle autre : cherchez-la
avec `Super+Space`, et faites un clic droit dessus dans le dock pour l’épingler. Pour en supprimer une,
choisissez **Remove a web app** dans le même menu, ou :

```bash
amethystora-webapp remove "Proton Mail"
```

Pour ouvrir un site comme application web une seule fois, sans l’installer :
`amethystora-webapp <address>`.

## Quel navigateur les exécute

Les applications web s’ouvrent dans votre navigateur par défaut, qui est Firefox tant que vous n’en
choisissez pas un autre, et vous suivent quand vous en changez. Seules les adresses `http` et `https`
peuvent devenir des applications web.

| Navigateur par défaut | Comment s’ouvre une application web |
| --- | --- |
| Brave, Chrome, Chromium, Edge, Vivaldi ou Opera | Dans la fenêtre d’application propre au navigateur. Elle partage les connexions, les mots de passe et les extensions du navigateur. |
| Firefox, LibreWolf, Zen, Floorp ou Waterfox | Dans une fenêtre sans onglets ni barre d’outils, avec son propre profil. Firefox n’a pas de fenêtre d’application : chaque application web garde donc ses propres connexions et ne voit pas celles du navigateur. |
| Tout autre | Dans un navigateur des deux lignes ci-dessus : un navigateur basé sur Chromium si vous en avez installé un, et sinon Firefox. |

Le profil d’une application web Firefox se trouve dans `~/.local/share/amethystora-webapp`, ou dans le
dossier du navigateur sous `~/.var/app` quand le navigateur est un Flatpak. Supprimer l’application web
le supprime, connexions comprises.
