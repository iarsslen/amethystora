# Sécurité

Amethystora est renforcé au-delà des réglages par défaut de Fedora, et le dit clairement : tout ce qui
suit peut être vérifié, et la plupart peut être modifié si cela vous gêne.

## Voir où vous en êtes

Ouvrez **Sécurité** depuis la grille d’applications, ou exécutez :

```bash
ame security status
```

Les deux montrent ce que font réellement les paramètres de sécurité en ce moment, avec ce qu’il faut
faire pour tout ce qui est désactivé, et aucun des deux ne modifie quoi que ce soit ni ne demande de mot
de passe. Dans l’application, ce qui requiert votre attention vient en premier, avec la commande qui le
corrige et un bouton qui l’exécute dans un terminal, et chacune des protections ci-dessous qui restent
désactivées tant que vous n’en voulez pas est à un bouton de distance. Pour un examen plus approfondi,
`ame security audit` fait passer à Lynis quelques centaines de vérifications et explique chaque
constat.

La page **Applications** de l’application liste ce à quoi chaque application Flatpak peut accéder
au-delà de son bac à sable, et ce qui en a été accordé sur cette machine
([Permissions des applications](#app-permissions)).

La page **Conteneurs** de l’application liste ce qui est installé hors de Flatpak : les conteneurs
créés par `amepkg`, les applications de votre grille d’applications qui en proviennent, et ce qui a été
construit depuis l’AUR, chacun avec la date de sa dernière mise à jour. Le rapport le signale quand
l’un d’eux est resté deux semaines sans mise à jour. [Conteneurs](software.md#containers).

Quand quelque chose requiert votre attention, **Demander à l’agent** le confie à
l’[agent IA](ai-agent.md), qui l’examine dans un terminal et ne modifie rien tant que vous n’êtes pas
d’accord.

## Activé dès le départ

- **Les mises à jour doivent être signées.** Seules les images signées avec la clé d’Amethystora sont
  installées : une image altérée ou substituée est donc refusée.
  [Mises à jour](updates.md#signed-updates).
- **Le pare-feu refuse les connexions entrantes.** Sont autorisés à entrer la découverte des
  imprimantes et des périphériques, le partage de fichiers Windows, la configuration IPv6 et
  GSConnect ; votre tailnet Tailscale est de confiance. Pour laisser entrer autre chose, comme un
  serveur de développement que vous voulez joindre depuis votre téléphone, utilisez l’application
  **Pare-feu** ou `sudo firewall-cmd --add-port=8080/tcp` (ajoutez `--permanent` pour le conserver
  après un redémarrage).
- **Dix mots de passe erronés d’affilée** verrouillent un compte pendant dix minutes. Déverrouillez-le
  plus tôt depuis un autre compte administrateur avec `sudo faillock --user <name> --reset`.
- **Les échecs de connexion répétés depuis le réseau** font bloquer l’adresse : cinq échecs en dix
  minutes coûtent une heure, et chaque nouveau bannissement de la même adresse dure plus longtemps,
  jusqu’à une journée. Cela surveille le serveur SSH, la seule chose ici à laquelle on peut se connecter
  depuis le réseau, et laisse le tailnet tranquille. `ame security addresses` liste ce qui est bloqué,
  et `ame security addresses <address>` laisse de nouveau entrer une adresse.
- **Le serveur SSH est désactivé,** et refuse les connexions root quand vous l’activez.
- **Les applications ne peuvent pas espionner le clavier les unes des autres.** Les applications
  Flatpak se voient refuser X11 et les périphériques d’entrée
  ([Installer des logiciels](software.md#what-flatpak-apps-may-not-do)), et l’outil de réaffectation
  des touches, qui lit chaque touche, est désactivé tant que vous ne le demandez pas.
- **Le noyau est durci :** la mémoire est effacée au moment où elle est attribuée, les adresses du
  noyau sont masquées, les programmes ne peuvent pas lire la mémoire les uns des autres, et les modules
  rarement utilisés (anciens protocoles réseau et systèmes de fichiers, FireWire) ne peuvent pas se
  charger. `gdb -p` sur un processus que vous n’avez pas lancé nécessite `sudo`.
- **Le noyau refuse d’être réécrit pendant qu’il tourne.** Le verrouillage bloque le chargement de
  modules non fiables, l’écriture dans `/dev/mem` et le traçage de la mémoire du noyau avec BPF : une
  compromission de root s’arrête donc au redémarrage suivant. Il nécessite Secure Boot activé et la clé
  enregistrée ([Matériel](hardware.md#secure-boot)). Sur une machine où Secure Boot ne peut pas être
  activé, retirez-le avec `sudo rpm-ostree kargs --delete=lockdown=integrity`. Les images NVIDIA ne
  l’utilisent pas.
- **Ce qui survivrait à un redémarrage est surveillé, et vous êtes prévenu.** Le journal d’audit
  enregistre les modifications des comptes, de qui peut utiliser `sudo`, de ce qui démarre tout seul
  (vos entrées de démarrage automatique, vos propres services systemd, les fichiers de démarrage du
  shell) et des paramètres de sécurité, ainsi que chaque programme qui ouvre un périphérique d’entrée.
  La veille de sécurité le lit toutes les 15 minutes et indique ce qui a changé et quel programme l’a
  changé. [La veille de sécurité](#the-security-watcher).
- **Une analyse antivirus s’exécute chaque semaine** sur vos dossiers personnels et temporaires, et
  **Lynis audite les paramètres chaque mois.** Par défaut, ni l’une ni l’autre ne supprime ni ne
  déplace quoi que ce soit : un faux positif qui retire un fichier que vous vouliez est pire que la
  plupart de ce qu’elles supprimeraient. `ame security scan` montre ce qu’a trouvé la dernière analyse,
  et `ame security scan now` en lance une. [Rechercher des virus](#scanning-for-viruses) fait de même
  dans une fenêtre, et [Paramètres](#settings) permet aux analyses de mettre en quarantaine ou de
  supprimer ce qu’elles trouvent.

## La veille de sécurité

Toutes les 15 minutes, ou au fil des événements avec la [surveillance en temps réel](#settings)
activée, la veille examine :

- **Le journal d’audit** : les comptes, les règles `sudo`, ce qui démarre tout seul, les paramètres de
  sécurité et les modules du noyau chargés depuis une session, chacun avec le programme qui a fait la
  modification. Un programme qui ouvre directement le clavier est signalé la première fois que ce
  programme le fait ; les jeux et les outils de réaffectation des touches le font aussi.
- **Le journal** : un compte verrouillé après des mots de passe erronés, trois mots de passe `sudo` ou
  administrateur erronés ou plus, et les périphériques USB que la
  [protection USB](#block-usb-devices-you-did-not-plug-in) a bloqués.
- **`/etc` par rapport à l’image** : l’image garde sa propre copie de `/etc` dans `/usr/etc` ; un
  paramètre de sécurité modifié, ou un fichier de `/etc` qui remplace un de ceux de l’image dans
  `/usr/lib`, apparaît donc comme **Paramètres de l’image** dans le rapport.
- **Ce qui ne devrait pas exister sur ce système** : un programme setuid hors de `/usr`,
  `/etc/ld.so.preload`, un fichier ordinaire dans `/dev`, un module du noyau qui n’est pas fourni avec
  l’image ou n’est pas signé, et une interface réseau qui lit chaque paquet. C’est la **Recherche de
  rootkits** dans le rapport.
- **Ce qui accepte des connexions** : chaque programme qui écoute sur le réseau, que tous les appareils
  de votre tailnet peuvent joindre. Un nouveau est signalé une fois.
- **Ce que votre session trouve en premier** : un programme dans `~/.local/bin`, `~/bin` ou le dossier
  de Homebrew portant le nom d’une des commandes du système, que votre shell exécute à la place de la
  vraie. Un faux `sudo` ou `ssh` à cet endroit est une vieille ruse pour intercepter un mot de passe :
  ceux-là sont donc signalés le plus fort ; le dossier de Homebrew ne compte que pour eux. Et un lanceur
  de votre grille d’applications qu’aucun export de conteneur n’a créé. Chacun est signalé quand il
  apparaît, et de nouveau s’il change.
- **La protection du réseau**, quand elle est activée : chaque connexion qu’elle a bloquée, avec la
  façon de l’autoriser de nouveau, et ce qu’elle a reconnu sans bloquer quand la règle le juge grave.
  [Protection du réseau](#network-protection).
- **Le rapport lui-même** : quand une vérification qui détecte la désactivation d’une protection,
  comme le pare-feu, les mises à jour signées ou le journal d’audit, cesse d’être au vert.

Tout ce qui est nouveau fait l’objet d’une notification, et attend dans le rapport jusqu’à ce que vous
le lisiez :

```bash
ame security events
```

`ame security events now` regarde d’abord. Si c’est vous qui avez fait la modification, ou installé
quelque chose qui l’a faite, il n’y a rien à faire.

## Permissions des applications

Chaque application Flatpak s’exécute dans un bac à sable, et ses permissions disent jusqu’où, au-delà
de celui-ci, elle peut accéder sans vous le demander. La page **Applications** de l’application
Sécurité, et `ame security apps` dans un terminal, listent pour chaque application ce à quoi elle peut
accéder, et indiquent ce qui en a été accordé sur cette machine plutôt que demandé par l’application
elle-même :

| Ce qu’elle peut faire | Ce que cela signifie |
| --- | --- |
| Communiquer avec tous les services de votre session ou du système, utiliser le service Flatpak ou le systemd de votre session, ou placer un programme là où il démarre à votre prochaine connexion | Elle peut sortir de son bac à sable : tout ce qui s’y exécute peut faire tout ce que vous pouvez faire |
| Utiliser X11, ou lire les périphériques d’entrée | Elle peut voir ce que vous tapez dans d’autres applications. L’image retire les deux à toutes les applications : une application ne les a donc que s’ils lui ont été rendus |
| Utiliser tous les périphériques | Caméras, clés de sécurité et manettes de jeu, sans demander |
| Lire et modifier vos fichiers, ou seulement les lire | Tout ce qui se trouve dans votre dossier personnel, ou chaque fichier que vous pouvez ouvrir |
| Utiliser vos clés SSH ou GPG, ou lire votre trousseau | Se connecter, signer ou déchiffrer en votre nom, ou lire chaque mot de passe que vous avez enregistré |

Ce qu’une application demande par un portail, comme un fichier que vous choisissez pour elle, est
demandé à chaque fois et n’est pas listé. Le rapport de sécurité signale quand une application peut
sortir de son bac à sable, et quand X11 ou les périphériques d’entrée ont été rendus à une application.
Si ce n’était pas voulu, modifiez-le dans **Flatseal**, ou retirez tout ce que vous avez accordé à une
application avec **Retirer ce que vous avez accordé** sur la page Applications, ou :

```bash
ame security apps reset
```

## Partager des fichiers sans ce qu’ils disent de vous

Les photos, les documents et les enregistrements contiennent plus que ce qu’ils montrent : où une photo
a été prise et avec quel téléphone, qui a écrit un document et quand. **Metadata Cleaner** montre ce
qu’un fichier dit de vous et en enregistre une copie sans ces informations. Ouvrez-le depuis la grille
d’applications et ajoutez les fichiers avant de les envoyer ou de les publier.

## Rechercher des virus

**Analyse antivirus** dans l’application **Sécurité** (ou `amethystora-security scan`) analyse quand
vous le demandez :

- **Votre dossier personnel**, hormis les caches.
- **Un fichier ou un dossier** : choisissez-le, ou déposez-le n’importe où sur la fenêtre.
- **Toute la machine** : tous les dossiers personnels et temporaires, comme le fait l’analyse
  hebdomadaire. Elle ne demande pas de mot de passe et continue si vous fermez la fenêtre. Ce qu’elle
  trouve est conservé là où seul un administrateur peut le lire : le voir demande donc bien votre mot
  de passe.

Une analyse que vous lancez s’exécute en votre nom : elle vérifie donc ce que votre compte peut lire.
Par défaut, rien de ce qu’elle trouve n’est supprimé, mis en quarantaine ni déplacé : le résultat liste
chaque fichier, avec **Afficher dans Fichiers**, et vous laisse décider. Une détection peut être un faux
positif : vérifiez donc d’où vient un fichier avant de le supprimer, puis relancez l’analyse. Si vous
avez réglé les analyses pour mettre en quarantaine ou supprimer, l’application demande votre mot de
passe une fois l’analyse terminée et indique ce qu’il est advenu de chaque fichier. Les analyses que
vous avez lancées sont listées dans `~/.local/state/amethystora/security-scans.json`.

## Paramètres

```bash
ame security settings
```

- **Ce qu’il advient de ce que trouve une analyse antivirus** : `report` (par défaut) le laisse où il
  est, `quarantine` le déplace dans `/var/lib/amethystora/quarantine`, où rien ne peut l’ouvrir ni
  l’exécuter, et `delete` le supprime. Cela s’applique à l’analyse hebdomadaire, aux analyses que vous
  lancez dans l’application et à l’analyse en temps réel. Chaque fichier est vérifié de nouveau avant
  que quoi que ce soit ne lui soit fait. `ame security scan quarantine` liste ce qui est en
  quarantaine, et `ame security scan restore` remet un fichier en place et peut dire à l’antivirus de
  laisser tranquille ce fichier précis à l’avenir.
- **Surveillance en temps réel** : `off` (par défaut) ou `on`. Activée, la veille de sécurité lit chaque
  modification au moment où le journal d’audit l’enregistre, et chaque fichier écrit dans un dossier
  personnel est analysé au moment où il est fermé. Cela coûte un peu de processeur pendant l’écriture
  de fichiers, et l’analyse commence une fois les premières signatures de virus téléchargées.
- **Protection du réseau** : `off` (par défaut), `watch` ou `block`.
  [Protection du réseau](#network-protection).

Les trois sont conservés dans `/etc/amethystora/security.conf`. La commande applique un changement
immédiatement ; une modification du fichier à la main s’applique au prochain redémarrage.

## Ce qui vaut la peine d’être activé

### Clés de sécurité

Une clé de sécurité FIDO2 (YubiKey, Thetis, ou un modèle à empreinte digitale comme la YubiKey Bio)
peut vous connecter, déverrouiller l’écran et approuver `sudo` et les demandes d’administration à la
place de votre mot de passe :

```bash
ame security key
```

Choisissez **Add a fingerprint key** pour un modèle à empreinte digitale, afin que la clé vérifie votre
empreinte et pas seulement un contact. La clé a d’abord besoin d’un code PIN, et un modèle à empreinte
digitale d’un doigt enregistré : définissez-les dans Firefox à l’adresse `about:webauthn`, ou avec
`ykman fido fingerprints add` sur une YubiKey Bio. Enregistrez une deuxième clé en secours. Votre mot de
passe continue de fonctionner chaque fois qu’aucune clé enregistrée n’est branchée.

### Connexion par empreinte digitale

Sur une machine dotée d’un lecteur d’empreintes, un doigt peut vous connecter, déverrouiller l’écran et
approuver `sudo` et les demandes d’administration, et votre mot de passe continue de fonctionner à
côté :

```bash
ame security fingerprint
```

**Add a finger** en enregistre un ; enregistrez-en un deuxième en secours. **Paramètres › Système ›
Utilisateurs** fait la même chose sous **Connexion par reconnaissance d’empreintes**. Deux choses demandent
encore le mot de passe : la phrase de passe du disque au démarrage, et le trousseau, qu’une connexion
par empreinte laisse verrouillé jusqu’à ce qu’une application en ait besoin. Les lecteurs qui
fonctionnent sont listés sur [fprint.freedesktop.org](https://fprint.freedesktop.org/supported-devices.html).

### Contrôle parental

Pour le compte d’un enfant, faites-en un compte standard, pas un administrateur, dans **Paramètres ›
Système › Utilisateurs**, puis ouvrez **Contrôle parental** depuis la grille d’applications, ou depuis
la page de ce compte dans Paramètres. Il détermine quelles applications installées le compte peut
ouvrir, s’il peut installer des applications et jusqu’à quelle classification d’âge, et, à partir de
GNOME 50, combien de temps par jour il peut utiliser l’ordinateur et à partir de quelle heure le soir il
ne le peut plus. Quand le temps est écoulé, l’écran se verrouille.

### Sauvegardes

```bash
ame backup
```

Une sauvegarde restic quotidienne vers un dépôt dont un rançongiciel présent sur cette machine ne peut
rien supprimer. La sauvegarde ne fait qu’ajouter au dépôt et ne supprime jamais les anciens
instantanés : un dépôt en ajout seul à l’autre bout conserve donc tout ce qui a été sauvegardé avant
une attaque. La commande explique comment en mettre un en place sur rest-server, Borg, un stockage
objet avec immuabilité, ou un disque USB que vous débranchez entre deux sauvegardes. `ame backup now`
sauvegarde immédiatement, et `ame backup snapshots` liste ce qui s’y trouve.

Chaque sauvegarde conserve aussi votre configuration à côté de vos fichiers : l’image et le flux que
vous suivez, vos applications Flatpak et leur provenance, vos paquets Homebrew, les conteneurs créés par
`amepkg` avec ce que vous y avez installé, les extensions GNOME que vous aviez activées et votre thème.
Aucun mot de passe, aucune clé ni aucun jeton n’y figure. Sur une nouvelle machine, faites pointer
`ame backup` vers le même dépôt avec le même mot de passe, puis :

```bash
ame restore-setup
```

La commande montre d’abord ce qu’elle ferait, et ne fait que les parties que vous choisissez : passer à
la même image, via `ame system rebase`, qui n’accepte que des images signées ; installer les
applications et les paquets Homebrew ; recréer les conteneurs et y réinstaller ce qu’ils contenaient ;
réactiver les extensions ; appliquer le thème. `ame restore-setup <snapshot>` choisit une configuration
plus ancienne. Vos fichiers eux-mêmes reviennent avec restic.

### Protection contre les rançongiciels

```bash
ame security ransomware
```

Toutes les heures, un instantané en lecture seule de chaque dossier personnel de cette machine, conservé
dans `/var/home/.snapshots`. Un rançongiciel qui s’exécute en votre nom peut chiffrer tout ce dans quoi
vous pouvez écrire, et un instantané n’est pas quelque chose dans quoi vous pouvez écrire : en modifier
ou en supprimer un exige un administrateur. Tous les instantanés de la dernière journée sont conservés,
puis un par jour pendant deux semaines. Le rapport le signale quand le plus récent date de plus de
quelques heures.

Pour récupérer des fichiers, exécutez `ame security ransomware restore` et choisissez le moment auquel
revenir. **Open it in Files** montre votre dossier personnel tel qu’il était alors, pour y copier des
fichiers ; **Put a folder back** recopie tout un dossier à sa place, en remplaçant les fichiers qu’il
contient et en laissant ceux qu’il ne contient pas, comme ceux qu’un rançongiciel a renommés. Les
fichiers des autres ne sont pas visibles dans un instantané, et les vôtres ne leur sont pas visibles.

Elle nécessite les dossiers personnels sur un sous-volume btrfs à part, ce que l’installateur met en
place sur un disque sauf s’il a été partitionné à la main. Le coût est l’espace disque : un instantané
retient ce qui a été modifié ou supprimé depuis, si bien qu’un fichier que vous supprimez pour faire de
la place ne libère son espace que lorsque le dernier instantané qui le contient disparaît, jusqu’à deux
semaines plus tard. Les instantanés ne sont jamais supprimés pour faire de la place, car un rançongiciel
qui réécrit chaque fichier supprimerait alors ceux d’avant son passage. La désactiver propose de les
supprimer.

Les instantanés se trouvent sur le même disque, et un rançongiciel qui obtient les droits
d’administrateur peut les supprimer. Gardez aussi une [sauvegarde](#backups) ailleurs.

### Déverrouiller le disque avec le TPM

```bash
ame security disk-unlock
```

Au lieu que vous saisissiez la phrase de passe du disque à chaque démarrage, le TPM de la machine
fournit la clé, mais seulement tant que Secure Boot est activé et que les clés de signature sont celles
enregistrées lors de la configuration. Ajoutez un code PIN si vous voulez que le disque exige aussi
quelque chose que vous connaissez. Votre phrase de passe continue de fonctionner : un TPM réinitialisé
ne vous bloque donc jamais dehors. Cela nécessite un disque chiffré lors de l’installation.

### Bloquer les périphériques USB que vous n’avez pas branchés

```bash
ame security usb
```

Un périphérique USB peut prétendre être un clavier et taper tout seul, et un enregistreur de frappe
matériel peut se glisser entre un vrai clavier et la machine. La protection USB autorise ce qui est
branché au moment où vous la configurez et bloque tout nouveau périphérique jusqu’à ce que vous
l’autorisiez avec `ame security usb allow`. Elle est désactivée par défaut, car une machine qui
bloquerait son propre clavier au premier démarrage serait inutilisable.

### Protection des navigateurs

```bash
ame security browser
```

Une extension voit chaque page que vous ouvrez, et c’est ainsi qu’arrivent la plupart des voleurs de
mots de passe. Avec la protection des navigateurs activée, les navigateurs n’installent que les
extensions d’une liste : les gestionnaires de mots de passe Bitwarden, 1Password, Proton Pass et
KeePassXC, et celles que vous ajoutez avec `ame security browser allow <id>`. Les pages web sont aussi
tenues à l’écart des périphériques USB, série, HID et Bluetooth. Elle couvre Firefox, Brave, Chrome,
Chromium et Edge, qu’ils soient installés maintenant ou plus tard, pour chaque compte de la machine.
Les autres navigateurs ne sont pas couverts.

Autorisez les extensions que vous utilisez avant de l’activer. Firefox supprime celles qui ne sont pas
sur la liste, avec leurs paramètres, à son prochain démarrage ; les autres navigateurs désactivent les
leurs. Firefox affiche l’ID de chaque extension dans `about:support`, sous Modules complémentaires, et
les autres sur leur page d’extensions avec le mode développeur activé. Les thèmes, dictionnaires et
paquets linguistiques de Firefox ne sont pas concernés.

Ce que vous avez autorisé se trouve dans `/etc/amethystora/browser-extensions`, un ID par ligne. Pour en
retirer un, supprimez sa ligne et exécutez de nouveau `ame security browser on`. Elle est désactivée
par défaut : Firefox est fourni exactement tel que Fedora le construit, et ce qu’il peut installer est
votre décision, pas celle de l’image.

### Protection du réseau

```bash
ame security settings network
```

Suricata inspecte chaque connexion que cette machine établit et reçoit au moyen des règles Emerging
Threats Open, qu’il télécharge chaque jour :

- **`watch`** signale ce qu’il reconnaît et ne bloque rien. Commencez par là : une semaine de ce mode
  montre ce que le blocage gênerait.
- **`block`** coupe aussi les connexions vers les logiciels malveillants connus et leurs serveurs de
  commande, les exploits, les pages d’hameçonnage et les mineurs de cryptomonnaie, ainsi que vers les
  adresses des listes de blocage Spamhaus et DShield. Ce que les règles reconnaissent avec moins de
  certitude est seulement signalé.

Chaque connexion bloquée fait l’objet d’une notification. **Réseau** dans l’application **Sécurité**
liste ce qui a été bloqué et signalé, tout comme `ame security connections`. Si une connexion venait de
vous et était voulue, **Autoriser**, ou `ame security connections allow <rule>`, exclut cette règle-là
sur cette machine, et `ame security connections block <rule>` la rétablit.

Quoi qu’il arrive, vos connexions continuent de fonctionner : pendant que Suricata démarre, redémarre,
prend du retard ou s’arrête, elles passent sans inspection plutôt que de ne pas passer du tout. Une
connexion chiffrée est inspectée jusqu’à sa poignée de main, le nom du serveur et le certificat, car ce
qui suit ne peut pas être lu. Son journal conserve ce qu’il a reconnu et rien d’autre, jamais une liste
des sites que vous visitez. Il inspecte les connexions propres à cette machine, pas ce qu’elle relaie
pour des machines virtuelles ou des conteneurs exécutés en tant que root, et occupe quelques centaines
de mégaoctets de mémoire. Elle est désactivée par défaut : bloquer quoi que ce soit est une décision
qui concerne votre propre trafic, et elle vous revient.

### Réaffectation des touches

Input Remapper s’exécute en tant que root et lit chaque touche tapée dans chaque application. C’est ce
dont la réaffectation a besoin, et à tous les autres égards c’est un enregistreur de frappe : il est
donc livré désactivé. Si vous réaffectez des touches ou des boutons de souris, activez-le avec
`ame security input-remapper`.
