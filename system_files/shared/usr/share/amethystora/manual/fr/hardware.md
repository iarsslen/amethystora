# Matériel

Amethystora fonctionne le mieux sur du matériel que Linux prend bien en charge : les cartes graphiques
Intel et AMD, et les portables que leurs fabricants certifient pour Linux. La plupart des choses
fonctionnent dès qu’elles sont branchées ; cette page traite de celles qui demandent une étape de votre
part.

## Secure Boot

Laissez Secure Boot activé. Grâce à lui, la machine ne démarre qu’un noyau qu’elle a vérifié, et le
[verrouillage](security.md) du noyau repose sur une base solide.

Les modules du noyau intégrés à l’image, pour les stations d’accueil DisplayLink et les caméras
virtuelles, sont signés avec la clé propre à Amethystora, et il faut dire une fois au micrologiciel de
lui faire confiance :

```bash
ame security secure-boot
```

Redémarrez : un écran bleu apparaît avant que le système ne démarre, le gestionnaire MOK. Choisissez
**Enroll MOK**, puis **Continue**, puis **Yes**, et saisissez le mot de passe `amethystora`. Cet écran
utilise une disposition de clavier américaine (QWERTY) quelle que soit la vôtre, ce qui compte si votre
clavier place les lettres ailleurs : sur un clavier AZERTY, tapez `q,ethystorq`.
`ame security status` vous indique si les clés sont enregistrées.

Si Secure Boot est désactivé, une notification le signale une fois. Activez-le dans les paramètres du
micrologiciel de la machine, puis exécutez la commande ci-dessus.

## Graphismes

- **Intel et AMD** fonctionnent d’emblée. L’image pour développeurs ajoute ROCm pour le calcul GPU sur
  AMD.
- **NVIDIA** nécessite les images `-nvidia-open`, qui contiennent le pilote noyau ouvert de NVIDIA
  ([Installation](installing.md#pick-an-image)). Le pilote NVIDIA est construit pour la machine et
  signé avec sa propre clé : les images NVIDIA n’utilisent donc pas le verrouillage du noyau.
- **Vous avez installé l’image sans le pilote NVIDIA sur une machine dotée d’une carte NVIDIA ?** Il
  n’y a pas d’installateur pour les images NVIDIA : c’est donc ainsi que démarrent la plupart des
  machines NVIDIA. Quelques minutes après le premier démarrage, une notification propose
  **Switch images…**, qui ouvre `ame system rebase` sur l’image `-nvidia-open` correspondante ; la
  commande n’accepte que des images signées et demande avant de changer. Une image NVIDIA sur une
  machine sans carte NVIDIA propose l’image sans le pilote, qui garde le verrouillage activé. Rien ne
  change de lui-même, le message n’apparaît qu’une fois par machine, et **Don't ask again** l’arrête
  définitivement.

## Stations d’accueil et écrans

- Les **stations d’accueil DisplayLink** fonctionnent avec le pilote intégré à l’image. Avec Secure
  Boot activé, la station reste éteinte tant que la clé ci-dessus n’est pas enregistrée.
- La **luminosité des écrans externes** peut se régler en ligne de commande avec `ddcutil`, pour les
  écrans qui le prennent en charge.

## Disques

- Le **chiffrement** se choisit à l’installation et ne peut pas être ajouté après coup. Une fois
  activé, `ame security disk-unlock` permet au TPM de déverrouiller le disque au démarrage, sans que
  vous ayez à saisir la phrase de passe ([Sécurité](security.md#unlock-the-disk-with-the-tpm)).
- **ZFS** est disponible sur le flux `stable`.

## Imprimantes et scanners

La plupart des imprimantes sont détectées sur le réseau et fonctionnent directement, sans pilote. Des
pilotes pour les imprimantes HP et pour de nombreuses imprimantes Brother et laser plus anciennes sont
inclus pour les autres. Ajoutez une imprimante dans **Paramètres → Imprimantes**.

## Téléphones

- **Android :** GSConnect relie le téléphone au bureau : notifications, transfert de fichiers,
  presse-papiers partagé et SMS. Installez KDE Connect sur le téléphone et associez-les depuis les
  réglages rapides.
- **iPhone :** branchez-le et faites confiance à l’ordinateur sur le téléphone ; ses photos et ses
  fichiers apparaissent dans Fichiers.

## Claviers, souris et clés de sécurité

- **Souris de jeu :** le service qui les configure est inclus ; installez **Piper** depuis Bazaar pour
  modifier les boutons, l’éclairage et la résolution.
- **Réaffecter des touches :** `ame security input-remapper` active Input Remapper
  ([Sécurité](security.md#key-remapping) explique pourquoi il est désactivé au départ).
- Les **clés de sécurité FIDO2** peuvent remplacer votre mot de passe :
  [Sécurité](security.md#security-keys).

## Portables

Les portables Framework reçoivent leurs correctifs connus au premier démarrage, pour la mise en veille,
l’audio et le clavier, et le modèle 13 pouces une taille de texte adaptée à son écran. Gardez le
micrologiciel à jour sur toutes les machines : **Mises à jour** montre ce qui est disponible, ou dans
un terminal :

```bash
fwupdmgr get-updates
fwupdmgr update
```

[Micrologiciels](updates.md#firmware) en dit plus.

## Caméras

Les caméras virtuelles (celle d’OBS, par exemple) fonctionnent sans rien installer, grâce au module
loopback intégré à l’image.
