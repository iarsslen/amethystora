# Sicherheit

Amethystora ist über die Vorgaben von Fedora hinaus gehärtet und sagt das offen: Alles hier unten lässt
sich überprüfen, und das meiste lässt sich ändern, wenn es Ihnen im Weg ist.

## Sehen, wo Sie stehen

Öffnen Sie **Sicherheit** in der Anwendungsübersicht oder führen Sie aus:

```bash
ame security status
```

Beides zeigt, was die Sicherheitseinstellungen gerade tatsächlich tun, und was bei allem zu tun ist, das
nicht stimmt, und keines von beiden ändert etwas oder fragt nach einem Passwort. In der App steht zuerst,
was Ihre Aufmerksamkeit braucht, mit dem Befehl, der es behebt, und einem Knopf, der ihn in einem Terminal
ausführt, und die Schutzmaßnahmen weiter unten, die ausgeschaltet bleiben, bis Sie sie wollen, sind
jeweils nur einen Knopfdruck entfernt. Für einen genaueren Blick lässt `ame security audit` Lynis einige
hundert Prüfungen durchlaufen und erklärt jeden Fund.

Die Seite **Apps** der App listet auf, worauf jede Flatpak-App über ihre Sandbox hinaus zugreifen kann und
was davon auf diesem Rechner gewährt wurde ([App-Berechtigungen](#app-permissions)).

Die Seite **Container** der App listet auf, was außerhalb von Flatpak installiert ist: die Container, die
`amepkg` erstellt hat, die Apps in Ihrer Anwendungsübersicht, die daraus stammen, und was aus dem AUR
gebaut wurde, jeweils mit dem Zeitpunkt der letzten Aktualisierung. Der Bericht meldet es, wenn einer zwei
Wochen ohne Aktualisierung geblieben ist. [Container](software.md#containers).

Wenn etwas Ihre Aufmerksamkeit braucht, übergibt **Den Agenten fragen** es an den
[KI-Agenten](ai-agent.md), der in einem Terminal nachforscht und nichts ändert, bis Sie zustimmen.

## Von Anfang an eingeschaltet

- **Aktualisierungen müssen signiert sein.** Nur mit dem Schlüssel von Amethystora signierte Abbilder
  werden installiert, sodass ein manipuliertes oder untergeschobenes Abbild abgelehnt wird.
  [Aktualisierungen](updates.md#signed-updates).
- **Die Firewall lehnt eingehende Verbindungen ab.** Hereingelassen werden die Erkennung von Druckern und
  Geräten, Windows-Dateifreigaben, die IPv6-Einrichtung und GSConnect; Ihrem Tailscale-Tailnet wird
  vertraut. Um etwas anderes hereinzulassen, etwa einen Entwicklungsserver, den Sie von Ihrem Telefon aus
  erreichen möchten, verwenden Sie die App **Firewall** oder `sudo firewall-cmd --add-port=8080/tcp`
  (fügen Sie `--permanent` hinzu, damit es einen Neustart überdauert).
- **Zehn falsche Passwörter in Folge** sperren ein Konto für zehn Minuten. Entsperren Sie es vorher von
  einem anderen Administratorkonto aus mit `sudo faillock --user <name> --reset`.
- **Wiederholt fehlgeschlagene Anmeldungen über das Netzwerk** führen zur Sperrung der Adresse: Fünf
  Fehlschläge innerhalb von zehn Minuten kosten eine Stunde, und jede weitere Sperre derselben Adresse
  dauert länger, bis zu einem Tag. Überwacht wird der SSH-Server, das Einzige hier, bei dem man sich über
  das Netzwerk anmelden kann, und das Tailnet bleibt unberührt. `ame security addresses` listet auf, was
  gesperrt ist, und `ame security addresses <address>` lässt eine Adresse wieder herein.
- **Der SSH-Server ist ausgeschaltet** und lehnt Root-Anmeldungen ab, wenn Sie ihn einschalten.
- **Anwendungen können die Tastatureingaben der anderen nicht belauschen.** Flatpak-Apps werden X11 und
  Eingabegeräte verweigert ([Software installieren](software.md#what-flatpak-apps-may-not-do)), und die
  Tastenumbelegung, die jeden Tastendruck liest, bleibt ausgeschaltet, bis Sie sie anfordern.
- **Der Kernel ist gehärtet:** Speicher wird bei der Vergabe gelöscht, Kernel-Adressen sind verborgen,
  Programme können den Speicher der anderen nicht lesen, und selten genutzte Module (alte
  Netzwerkprotokolle und Dateisysteme, FireWire) können nicht geladen werden. `gdb -p` für einen Prozess,
  den Sie nicht gestartet haben, erfordert `sudo`.
- **Der Kernel lässt sich nicht umschreiben, während er läuft.** Lockdown blockiert das Laden nicht
  vertrauenswürdiger Module, das Schreiben nach `/dev/mem` und das Ausspähen von Kernel-Speicher mit BPF,
  sodass eine Kompromittierung von root mit dem nächsten Neustart endet. Er braucht eingeschaltetes Secure
  Boot und den registrierten Schlüssel ([Hardware](hardware.md#secure-boot)). Auf einem Rechner, auf dem
  sich Secure Boot nicht einschalten lässt, entfernen Sie ihn mit
  `sudo rpm-ostree kargs --delete=lockdown=integrity`. Die NVIDIA-Abbilder verwenden ihn nicht.
- **Was einen Neustart überdauern würde, wird überwacht, und Sie werden informiert.** Das Audit-Protokoll
  zeichnet Änderungen an Konten auf, daran, wer `sudo` verwenden darf, an dem, was von selbst startet (Ihre
  Autostart-Einträge, Ihre eigenen systemd-Dienste, die Startdateien der Shell), und an den
  Sicherheitseinstellungen, sowie jedes Programm, das ein Eingabegerät öffnet. Der Sicherheitswächter liest
  es alle 15 Minuten und sagt, was sich geändert hat und welches Programm es geändert hat.
  [Der Sicherheitswächter](#the-security-watcher).
- **Ein Virenscan läuft jede Woche** über Ihre persönlichen und temporären Ordner, und **Lynis prüft die
  Einstellungen jeden Monat.** Standardmäßig löscht oder verschiebt keines von beiden etwas: Ein
  Fehlalarm, der Ihnen eine gewünschte Datei wegnimmt, ist schlimmer als das meiste, was er entfernen
  würde. `ame security scan` zeigt, was der letzte Scan gefunden hat, und `ame security scan now` startet
  einen. [Nach Viren suchen](#scanning-for-viruses) erledigt dasselbe in einem Fenster, und in den
  [Einstellungen](#settings) lassen Sie Scans ihre Funde in Quarantäne verschieben oder löschen.

## Der Sicherheitswächter

Alle 15 Minuten, oder bei eingeschalteter [Echtzeitüberwachung](#settings) sobald etwas geschieht, sieht
sich der Wächter Folgendes an:

- **Das Audit-Protokoll**: Konten, `sudo`-Regeln, was von selbst startet, die Sicherheitseinstellungen und
  Kernel-Module, die aus einer Anmeldesitzung heraus geladen wurden, jeweils mit dem Programm, das die
  Änderung vorgenommen hat. Ein Programm, das die Tastatur direkt öffnet, wird gemeldet, wenn dieses
  Programm es zum ersten Mal tut; Spiele und Tastenumbelegungen tun das ebenfalls.
- **Das Journal**: ein Konto, das nach falschen Passwörtern gesperrt wurde, drei oder mehr falsche
  Passwörter für `sudo` oder als Administrator, und USB-Geräte, die der
  [USB-Schutz](#block-usb-devices-you-did-not-plug-in) blockiert hat.
- **`/etc` im Vergleich zum Abbild**: Das Abbild behält seine eigene Kopie von `/etc` in `/usr/etc`, sodass
  eine geänderte Sicherheitseinstellung oder eine Datei in `/etc`, die eine des Abbilds in `/usr/lib`
  ersetzt, im Bericht unter **Einstellungen des Abbilds** erscheint.
- **Was es auf diesem System nicht geben sollte**: ein setuid-Programm außerhalb von `/usr`,
  `/etc/ld.so.preload`, eine gewöhnliche Datei in `/dev`, ein Kernel-Modul, das nicht mit dem Abbild kam
  oder nicht signiert ist, und eine Netzwerkschnittstelle, die jedes Paket liest. Das sind die
  **Rootkit-Prüfungen** im Bericht.
- **Was Verbindungen annimmt**: jedes Programm, das im Netzwerk lauscht und das jedes Gerät in Ihrem
  Tailnet erreichen kann. Ein neues wird einmal gemeldet.
- **Was Ihre Sitzung zuerst findet**: ein Programm in `~/.local/bin`, `~/bin` oder dem Ordner von
  Homebrew, das wie einer der Befehle des Systems heißt und das Ihre Shell anstelle des echten ausführt.
  Ein gefälschtes `sudo` oder `ssh` dort ist eine alte Methode, um ein Passwort abzufangen, deshalb werden
  diese am deutlichsten gemeldet; der Ordner von Homebrew zählt nur für diese. Und ein Starter in Ihrer
  Anwendungsübersicht, den kein Container-Export angelegt hat. Jedes wird gemeldet, wenn es auftaucht, und
  erneut, wenn es sich ändert.
- **Netzwerkschutz**, solange er eingeschaltet ist: jede Verbindung, die er blockiert hat, mit dem Weg, sie
  wieder zu erlauben, und was er ohne Blockieren erkannt hat, wenn die Regel es als ernst einstuft.
  [Netzwerkschutz](#network-protection).
- **Der Bericht selbst**: wenn eine Prüfung, die meldet, ob etwas ausgeschaltet wurde, etwa die Firewall,
  signierte Aktualisierungen oder das Audit-Protokoll, nicht mehr in Ordnung ist.

Alles Neue erscheint als Benachrichtigung und wartet im Bericht, bis Sie es lesen:

```bash
ame security events
```

`ame security events now` sieht zuerst nach. Wenn Sie die Änderung vorgenommen oder etwas installiert
haben, das sie vorgenommen hat, gibt es nichts zu tun.

## App-Berechtigungen

Jede Flatpak-App läuft in einer Sandbox, und ihre Berechtigungen sagen, wie weit die App ohne Nachfrage
darüber hinaus zugreifen kann. Die Seite **Apps** der Sicherheits-App und `ame security apps` in einem
Terminal listen für jede App auf, worauf sie zugreifen kann, und sagen, was davon auf diesem Rechner
gewährt wurde, statt von der App selbst verlangt:

| Was sie tun kann | Was das bedeutet |
| --- | --- |
| Mit jedem Dienst Ihrer Sitzung oder des Systems kommunizieren, den Flatpak-Dienst oder das systemd Ihrer Sitzung verwenden oder ein Programm dort ablegen, wo es bei Ihrer nächsten Anmeldung startet | Sie kann ihre Sandbox verlassen: Was darin läuft, kann alles, was Sie können |
| X11 verwenden oder die Eingabegeräte lesen | Sie kann sehen, was Sie in andere Apps eingeben. Das Abbild entzieht beides jeder App, also hat eine App es nur, wenn es ihr zurückgewährt wurde |
| Alle Geräte verwenden | Kameras, Sicherheitsschlüssel und Gamecontroller, ohne zu fragen |
| Ihre Dateien lesen und ändern oder nur lesen | Alles in Ihrem persönlichen Ordner oder jede Datei, die Sie öffnen können |
| Ihre SSH- oder GPG-Schlüssel verwenden oder Ihren Schlüsselbund lesen | Sich als Sie anmelden, signieren oder entschlüsseln oder jedes gespeicherte Passwort lesen |

Was eine App über ein Portal anfragt, etwa eine Datei, die Sie für sie auswählen, wird jedes Mal erfragt
und ist nicht aufgeführt. Der Sicherheitsbericht meldet, wenn eine App ihre Sandbox verlassen kann und
wenn einer X11 oder die Eingabegeräte zurückgegeben wurden. Wenn Sie das nicht beabsichtigt haben, ändern
Sie es in **Flatseal**, oder nehmen Sie alles, was Sie einer App gewährt haben, mit
**Gewährtes zurücknehmen** auf der Seite „Apps“ zurück, oder:

```bash
ame security apps reset
```

## Dateien teilen, ohne dass sie etwas über Sie verraten

Fotos, Dokumente und Aufnahmen tragen mehr in sich, als sie zeigen: wo ein Foto aufgenommen wurde und mit
welchem Telefon, wer ein Dokument geschrieben hat und wann. **Metadata Cleaner** zeigt, was eine Datei
über Sie verrät, und speichert eine Kopie ohne diese Angaben. Öffnen Sie es in der Anwendungsübersicht und
fügen Sie die Dateien hinzu, bevor Sie sie versenden oder veröffentlichen.

## Nach Viren suchen

**Virenscan** in der App **Sicherheit** (oder `amethystora-security scan`) scannt, wann immer Sie es
wünschen:

- **Ihr persönlicher Ordner**, außer Caches.
- **Eine Datei oder ein Ordner**: Wählen Sie sie aus, oder ziehen Sie sie an eine beliebige Stelle des
  Fensters.
- **Der ganze Rechner**: alle persönlichen und temporären Ordner, wie beim wöchentlichen Scan. Er fragt
  nach keinem Passwort und läuft weiter, wenn Sie das Fenster schließen. Was er findet, wird dort
  aufbewahrt, wo nur ein Administrator es lesen kann, daher fragt das Ansehen der Funde sehr wohl nach
  Ihrem Passwort.

Ein Scan, den Sie starten, läuft als Sie und prüft also, was Ihr Konto lesen kann. Standardmäßig wird
nichts, was er findet, gelöscht, unter Quarantäne gestellt oder verschoben: Das Ergebnis listet jede Datei
auf, mit **In Dateien anzeigen**, und überlässt Ihnen die Entscheidung. Ein Treffer kann ein Fehlalarm
sein, prüfen Sie also, woher eine Datei stammt, bevor Sie sie löschen, und scannen Sie dann erneut. Wenn
Sie Scans auf Quarantäne oder Löschen eingestellt haben, fragt die App nach Ende des Scans nach Ihrem
Passwort und sagt, was mit jeder Datei geschehen ist. Die Scans, die Sie ausgeführt haben, sind in
`~/.local/state/amethystora/security-scans.json` aufgeführt.

## Einstellungen

```bash
ame security settings
```

- **Was mit den Funden eines Virenscans geschieht**: `report` (die Vorgabe) lässt sie, wo sie sind,
  `quarantine` verschiebt sie nach `/var/lib/amethystora/quarantine`, wo nichts sie öffnen oder ausführen
  kann, und `delete` löscht sie. Das gilt für den wöchentlichen Scan, die Scans, die Sie in der App
  starten, und die Echtzeitprüfung. Jede Datei wird erneut geprüft, bevor irgendetwas mit ihr geschieht.
  `ame security scan quarantine` listet auf, was in Quarantäne ist, und `ame security scan restore` stellt
  eine Datei wieder her und kann den Scanner anweisen, genau diese Datei künftig in Ruhe zu lassen.
- **Echtzeitüberwachung**: `off` (die Vorgabe) oder `on`. Eingeschaltet liest der Sicherheitswächter jede
  Änderung, sobald das Audit-Protokoll sie aufzeichnet, und jede in einem persönlichen Ordner geschriebene
  Datei wird beim Schließen gescannt. Das kostet etwas Prozessorleistung, während Dateien geschrieben
  werden, und das Scannen beginnt, sobald die ersten Virensignaturen heruntergeladen sind.
- **Netzwerkschutz**: `off` (die Vorgabe), `watch` oder `block`.
  [Netzwerkschutz](#network-protection).

Alle drei stehen in `/etc/amethystora/security.conf`. Der Befehl wendet eine Änderung sofort an; eine
Bearbeitung der Datei von Hand gilt ab dem nächsten Neustart.

## Einschalten lohnt sich

### Sicherheitsschlüssel

Ein FIDO2-Sicherheitsschlüssel (YubiKey, Thetis oder ein Modell mit Fingerabdruck wie der YubiKey Bio)
kann Sie anmelden, den Bildschirm entsperren und `sudo`- sowie Administratorabfragen bestätigen, statt
Ihres Passworts:

```bash
ame security key
```

Wählen Sie **Add a fingerprint key** für ein Modell mit Fingerabdruck, damit der Schlüssel Ihren
Fingerabdruck prüft und nicht nur eine Berührung. Der Schlüssel braucht zuerst eine PIN, und ein Modell mit
Fingerabdruck einen registrierten Finger: Legen Sie beides in Firefox unter `about:webauthn` fest oder auf
einem YubiKey Bio mit `ykman fido fingerprints add`.
Registrieren Sie einen zweiten Schlüssel als Ersatz. Ihr Passwort funktioniert weiterhin, sobald kein
registrierter Schlüssel eingesteckt ist.

### Anmeldung per Fingerabdruck

Auf einem Rechner mit Fingerabdruckleser kann ein Finger Sie anmelden, den Bildschirm entsperren und
`sudo`- sowie Administratorabfragen bestätigen, und Ihr Passwort funktioniert daneben weiterhin:

```bash
ame security fingerprint
```

**Add a finger** registriert einen; registrieren Sie einen zweiten als Ersatz.
**Einstellungen › System › Benutzer** erledigt dasselbe unter **Fingerabdruck-Anmeldung**. Zwei Dinge
fragen weiterhin nach dem Passwort: die Passphrase der Festplatte beim Start und der Schlüsselbund, den
eine Anmeldung per Finger gesperrt lässt, bis eine App ihn braucht. Die Lesegeräte, die funktionieren,
sind unter [fprint.freedesktop.org](https://fprint.freedesktop.org/supported-devices.html) aufgeführt.

### Jugendschutz

Machen Sie das Konto eines Kindes unter **Einstellungen › System › Benutzer** zu einem Standardkonto,
nicht zu einem Administrator, und öffnen Sie dann **Jugendschutz** in der Anwendungsübersicht oder auf der
Seite dieses Kontos in den Einstellungen. Dort legen Sie fest, welche installierten Apps das Konto öffnen
darf, ob es Apps installieren darf und bis zu welcher Altersfreigabe, und ab GNOME 50, wie lange am Tag es
den Rechner benutzen darf und ab welcher Uhrzeit am Abend nicht mehr. Wenn die Zeit abgelaufen ist, wird
der Bildschirm gesperrt.

### Sicherungen

```bash
ame backup
```

Eine tägliche restic-Sicherung in ein Repository, aus dem Ransomware auf diesem Rechner nichts löschen
kann. Die Sicherung fügt dem Repository immer nur etwas hinzu und löscht nie alte Schnappschüsse, sodass
ein Repository am anderen Ende, das nur Anhängen erlaubt, alles behält, was vor einem Angriff gesichert
wurde. Der Befehl erklärt, wie Sie eines auf rest-server, Borg, einem Objektspeicher mit
Unveränderlichkeit oder einem USB-Laufwerk einrichten, das Sie zwischen den Sicherungen abziehen.
`ame backup now` sichert sofort, und `ame backup snapshots` listet auf, was vorhanden ist.

Jede Sicherung bewahrt neben Ihren Dateien auch Ihre Einrichtung auf: das Abbild und den Kanal, dem Sie
folgen, Ihre Flatpak-Apps und woher sie stammen, Ihre Homebrew-Pakete, die Container, die `amepkg`
erstellt hat, mit dem, was Sie darin installiert haben, die GNOME-Erweiterungen, die Sie eingeschaltet
hatten, und Ihr Thema. Keine Passwörter, Schlüssel oder Token gelangen hinein. Richten Sie auf einem neuen
Rechner `ame backup` mit demselben Passwort auf dasselbe Repository aus, und dann:

```bash
ame restore-setup
```

Es zeigt zuerst, was es tun würde, und erledigt nur die Teile, die Sie auswählen: zum selben Abbild
wechseln, über `ame system rebase`, das nur signierte Abbilder annimmt; die Apps und Homebrew-Pakete
installieren; die Container neu erstellen und installieren, was darin war; die Erweiterungen wieder
einschalten; das Thema setzen. `ame restore-setup <snapshot>` wählt eine ältere Einrichtung. Ihre Dateien
selbst holen Sie mit restic zurück.

### Ransomware-Schutz

```bash
ame security ransomware
```

Jede Stunde ein schreibgeschützter Schnappschuss jedes persönlichen Ordners auf diesem Rechner,
aufbewahrt in `/var/home/.snapshots`. Ransomware, die unter Ihrem Konto läuft, kann alles verschlüsseln,
was Sie schreiben können, und ein Schnappschuss ist nichts, was Sie schreiben können: Ihn zu ändern oder
zu löschen erfordert einen Administrator. Jeder Schnappschuss des letzten Tages wird aufbewahrt, und zwei
Wochen lang einer pro Tag. Der Bericht meldet, wenn der neueste älter als ein paar Stunden ist.

Um Dateien zurückzuholen, führen Sie `ame security ransomware restore` aus und wählen den Zeitpunkt, zu dem
Sie zurückkehren möchten. **Open it in Files** zeigt Ihren persönlichen Ordner, wie er damals war, zum
Herauskopieren; **Put a folder back** kopiert einen ganzen Ordner an seinen Platz zurück, ersetzt die
Dateien, die er enthält, und lässt die übrigen in Ruhe, etwa was Ransomware umbenannt hat. Die Dateien
anderer sind in einem Schnappschuss nicht sichtbar, und Ihre sind für sie nicht sichtbar.

Er braucht die persönlichen Ordner auf einem eigenen btrfs-Subvolume, so wie das Installationsprogramm
eine Festplatte einrichtet, sofern sie nicht von Hand partitioniert wurde. Der Preis ist Speicherplatz: Ein
Schnappschuss hält fest, was seitdem geändert oder gelöscht wurde, sodass eine Datei, die Sie löschen, um
Platz zu schaffen, ihren Platz erst freigibt, wenn der letzte Schnappschuss verschwindet, der sie enthält,
bis zu zwei Wochen später. Schnappschüsse werden nie gelöscht, um Platz zu schaffen, weil Ransomware, die
jede Datei umschreibt, sonst die von vorher löschen würde. Beim Ausschalten wird angeboten, sie zu löschen.

Schnappschüsse liegen auf derselben Festplatte, und Ransomware, die Administratorrechte erlangt, kann sie
löschen. Bewahren Sie zusätzlich eine [Sicherung](#backups) an einem anderen Ort auf.

### Festplatte mit dem TPM entsperren

```bash
ame security disk-unlock
```

Statt bei jedem Start die Passphrase der Festplatte einzugeben, übergibt das TPM des Rechners den
Schlüssel, aber nur, solange Secure Boot eingeschaltet ist und die Signaturschlüssel dieselben sind, die
bei der Einrichtung registriert waren. Fügen Sie eine PIN hinzu, wenn die Festplatte zusätzlich etwas
brauchen soll, das Sie wissen. Ihre Passphrase funktioniert weiterhin, sodass ein zurückgesetztes TPM Sie
nie aussperrt. Das erfordert eine Festplatte, die bei der Installation verschlüsselt wurde.

### USB-Geräte blockieren, die Sie nicht eingesteckt haben

```bash
ame security usb
```

Ein USB-Gerät kann sich als Tastatur ausgeben und selbst tippen, und ein Hardware-Keylogger kann zwischen
einer echten Tastatur und dem Rechner sitzen. Der USB-Schutz erlaubt, was bei der Einrichtung angeschlossen
ist, und blockiert alles Neue, bis Sie es mit `ame security usb allow` erlauben. Er ist standardmäßig
ausgeschaltet, weil ein Rechner, der beim ersten Start seine eigene Tastatur blockiert, unbenutzbar wäre.

### Browserschutz

```bash
ame security browser
```

Eine Erweiterung sieht jede Seite, die Sie öffnen, und so kommen die meisten Passwortdiebe herein. Mit
eingeschaltetem Browserschutz installieren Browser nur die Erweiterungen auf einer Liste: die
Passwortmanager Bitwarden, 1Password, Proton Pass und KeePassXC sowie die, die Sie mit
`ame security browser allow <id>` hinzufügen. Webseiten werden außerdem von USB-, seriellen, HID- und
Bluetooth-Geräten ferngehalten. Er gilt für Firefox, Brave, Chrome, Chromium und Edge, ob jetzt oder
später installiert, für jedes Konto auf dem Rechner. Andere Browser sind nicht abgedeckt.

Erlauben Sie die Erweiterungen, die Sie verwenden, bevor Sie ihn einschalten. Firefox entfernt beim
nächsten Start die, die nicht auf der Liste stehen, samt ihren Einstellungen; die anderen Browser schalten
ihre aus. Firefox zeigt die ID jeder Erweiterung in `about:support` unter Add-ons, die anderen auf ihrer
Erweiterungsseite bei eingeschaltetem Entwicklermodus. Themes, Wörterbücher und Sprachpakete in Firefox
bleiben unberührt.

Was Sie erlaubt haben, steht in `/etc/amethystora/browser-extensions`, eine ID pro Zeile. Um eine
zurückzunehmen, entfernen Sie ihre Zeile und führen Sie `ame security browser on` erneut aus. Er ist
standardmäßig ausgeschaltet: Firefox kommt genau so, wie Fedora es baut, und was es installieren darf,
entscheiden Sie, nicht das Abbild.

### Netzwerkschutz

```bash
ame security settings network
```

Suricata prüft jede Verbindung, die dieser Rechner aufbaut und annimmt, anhand der Regeln von Emerging
Threats Open, die es täglich herunterlädt:

- **`watch`** meldet, was es erkennt, und blockiert nichts. Beginnen Sie hier: Eine Woche davon zeigt,
  wobei das Blockieren im Weg wäre.
- **`block`** trennt außerdem Verbindungen zu bekannter Schadsoftware und ihren Steuerservern, zu Exploits,
  Phishing-Seiten und Kryptominern sowie zu Adressen auf den Sperrlisten von Spamhaus und DShield. Was die
  Regeln mit weniger Sicherheit erkennen, wird nur gemeldet.

Jede blockierte Verbindung erscheint als Benachrichtigung. **Netzwerk** in der App **Sicherheit** listet
auf, was blockiert und bemerkt wurde, ebenso `ame security connections`. Wenn eine Verbindung von Ihnen
stammte und gewollt war, lässt **Erlauben** oder `ame security connections allow <rule>` genau diese eine
Regel auf diesem Rechner aus, und `ame security connections block <rule>` nimmt sie wieder auf.

Was auch immer damit schiefgeht, Ihre Verbindungen funktionieren weiter: Während Suricata startet, neu
startet, nicht hinterherkommt oder anhält, passieren sie ungeprüft, statt gar nicht. Eine verschlüsselte
Verbindung wird bis zu ihrem Handshake geprüft, dem Servernamen und dem Zertifikat, weil sich das Folgende
nicht lesen lässt. Das Protokoll von Suricata behält, was es erkannt hat, und sonst nichts, nie eine Liste
der Websites, die Sie besuchen. Es prüft die eigenen Verbindungen dieses Rechners, nicht, was er für
virtuelle Maschinen oder als root laufende Container weiterleitet, und belegt einige hundert Megabyte
Arbeitsspeicher. Der Netzwerkschutz ist standardmäßig ausgeschaltet: Etwas zu blockieren ist eine
Entscheidung über Ihren eigenen Datenverkehr, und die treffen Sie.

### Tastenumbelegung

Input Remapper läuft als root und liest jeden Tastendruck in jeder Anwendung. Das braucht das Umbelegen,
und in jeder anderen Hinsicht ist es ein Keylogger, deshalb wird es ausgeschaltet ausgeliefert. Wenn Sie
Tasten oder Maustasten umbelegen, schalten Sie es mit `ame security input-remapper` ein.
