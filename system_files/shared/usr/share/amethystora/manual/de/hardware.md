# Hardware

Amethystora läuft am besten auf Hardware, die Linux gut unterstützt: Grafik von Intel und AMD und die
Laptops, die ihre Hersteller für Linux zertifizieren. Das meiste funktioniert, sobald es eingesteckt ist;
diese Seite handelt von dem, was einen Schritt von Ihnen braucht.

## Secure Boot

Lassen Sie Secure Boot eingeschaltet. Damit startet der Rechner nur einen Kernel, den er geprüft hat, und
der [Lockdown](security.md) des Kernels hat eine Grundlage.

Die im Abbild enthaltenen Kernel-Module für DisplayLink-Docks und virtuelle Kameras sind mit dem eigenen
Schlüssel von Amethystora signiert, und der Firmware muss einmal gesagt werden, dass sie ihm vertrauen
soll:

```bash
ame security secure-boot
```

Starten Sie neu, und ein blauer Bildschirm erscheint, bevor das System startet: der MOK-Manager. Wählen
Sie **Enroll MOK**, dann **Continue**, dann **Yes**, und geben Sie das Passwort `amethystora` ein. Der
Bildschirm verwendet eine US-Tastaturbelegung (QWERTY), unabhängig von Ihrer eigenen, was wichtig ist, wenn
Ihre Tastatur die Buchstaben anders anordnet: Auf einer deutschen Tastatur tippen Sie das y mit der
Z-Taste. `ame security status` sagt Ihnen, ob die Schlüssel registriert sind.

Wenn Secure Boot ausgeschaltet ist, weist einmalig eine Benachrichtigung darauf hin. Schalten Sie es in den
Firmware-Einstellungen des Rechners ein und führen Sie dann den obigen Befehl aus.

## Grafik

- **Intel und AMD** funktionieren sofort. Das Entwickler-Abbild fügt ROCm für GPU-Berechnungen auf AMD
  hinzu.
- **NVIDIA** braucht die `-nvidia-open`-Abbilder, die NVIDIAs offenen Kernel-Treiber mitbringen ([Installation](installing.md#pick-an-image)).
  Der NVIDIA-Treiber wird für den Rechner gebaut und mit dessen eigenem Schlüssel signiert, deshalb
  verwenden die NVIDIA-Abbilder keinen Kernel-Lockdown.
- **Das Abbild ohne NVIDIAs Treiber auf einem Rechner mit NVIDIA-Karte installiert?** Für die
  NVIDIA-Abbilder gibt es kein Installationsprogramm, also starten die meisten NVIDIA-Rechner so. Ein paar
  Minuten nach dem ersten Start bietet eine Benachrichtigung **Switch images…** an, was
  `ame system rebase` mit dem passenden `-nvidia-open`-Abbild öffnet; es nimmt nur signierte Abbilder an
  und fragt vor dem Wechsel nach. Ein NVIDIA-Abbild auf einem Rechner ohne NVIDIA-Karte bietet das Abbild
  ohne den Treiber an, das den Lockdown eingeschaltet lässt. Nichts wechselt von selbst, der Hinweis kommt
  einmal pro Rechner, und **Don't ask again** stellt ihn für immer ab.

## Docks und Bildschirme

- **DisplayLink-Docks** funktionieren mit dem im Abbild enthaltenen Treiber. Bei eingeschaltetem Secure
  Boot bleibt das Dock dunkel, bis der oben genannte Schlüssel registriert ist.
- **Die Helligkeit externer Monitore** lässt sich in der Befehlszeile mit `ddcutil` einstellen, bei
  Monitoren, die das unterstützen.

## Festplatten

- **Verschlüsselung** wird bei der Installation gewählt und lässt sich nachträglich nicht hinzufügen.
  Sobald sie eingeschaltet ist, lässt `ame security disk-unlock` das TPM die Festplatte beim Start
  entsperren, statt dass Sie die Passphrase eingeben ([Sicherheit](security.md#unlock-the-disk-with-the-tpm)).
- **ZFS** ist im Kanal `stable` verfügbar.

## Drucker und Scanner

Die meisten Drucker werden im Netzwerk gefunden und funktionieren einfach, ohne Treiber. Für den Rest sind
Treiber für HP-Drucker und viele Drucker von Brother sowie ältere Laserdrucker enthalten. Fügen Sie einen
Drucker unter **Einstellungen → Drucker** hinzu.

## Telefone

- **Android:** GSConnect verbindet das Telefon mit dem Desktop: Benachrichtigungen, Dateiübertragung, eine
  gemeinsame Zwischenablage und SMS. Installieren Sie KDE Connect auf dem Telefon und koppeln Sie beide
  über die Schnelleinstellungen.
- **iPhone:** Schließen Sie es an und vertrauen Sie dem Rechner auf dem Telefon; seine Fotos und Dateien
  erscheinen in Dateien.

## Tastaturen, Mäuse und Sicherheitsschlüssel

- **Gaming-Mäuse:** Der Dienst, der sie konfiguriert, ist enthalten; installieren Sie **Piper** aus
  Bazaar, um Tasten, Beleuchtung und Auflösung zu ändern.
- **Tasten neu belegen:** `ame security input-remapper` schaltet Input Remapper ein ([Sicherheit](security.md#key-remapping)
  erklärt, warum es zunächst ausgeschaltet ist).
- **FIDO2-Sicherheitsschlüssel** können Ihr Passwort ersetzen: [Sicherheit](security.md#security-keys).

## Laptops

Framework-Laptops erhalten beim ersten Start ihre bekannten Korrekturen für Bereitschaft, Audio und die
Tastatur, und das 13-Zoll-Modell eine zu seinem Bildschirm passende Textgröße. Halten Sie auf jedem Rechner
die Firmware aktuell: **Aktualisierungen** zeigt, was es gibt, oder in einem Terminal:

```bash
fwupdmgr get-updates
fwupdmgr update
```

[Firmware](updates.md#firmware) erklärt mehr.

## Kameras

Virtuelle Kameras (etwa die von OBS) funktionieren ohne zusätzliche Installation, über das im Abbild
enthaltene Loopback-Modul.
