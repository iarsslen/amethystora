# Sich zurechtfinden

Der Desktop ist GNOME, für die Tastatur eingerichtet. Alles hier funktioniert auch mit der Maus, aber
sobald Ihnen die Tasten in Fleisch und Blut übergegangen sind, greifen Sie nur noch selten zu ihr.

## Die obere Leiste

- **Links** die sechs Arbeitsflächen. Die, auf der Sie sich befinden, ist hervorgehoben; klicken Sie auf
  eine andere, um dorthin zu wechseln.
- **In der Mitte** die Uhr. Klicken Sie darauf oder drücken Sie `Super+V` für Benachrichtigungen und den
  Kalender.
- **Rechts** Anzeigen für Prozessor, Speicher und Netzwerk, dann das Systemmenü: WLAN, Ton, Energie und
  die übrigen Schnelleinstellungen.

Die Anzeigen und die Arbeitsflächen folgen den Farben des aktuellen [Themas](themes.md). Die Leiste kann
auch eigene [Widgets](widgets.md) anzeigen, die der KI-Agent für Sie erstellt.

## Dinge finden

- `Super+Space` sucht nach Apps, Dateien und Einstellungen und startet, was Sie auswählen.
- `Super` allein öffnet die Übersicht: alle offenen Fenster auf einmal, mit der Suche oben.
- `Super+A` zeigt alle installierten Apps.

Beide Suchen verzeihen Tippfehler in App-Namen: `calxu` findet trotzdem Calculator, den Taschenrechner.

## Die Zwischenablage

`Super+Shift+V` öffnet den Verlauf der Zwischenablage: die letzten 15 Dinge, die Sie kopiert haben.
Wählen Sie eines aus, um es erneut zu kopieren, tippen Sie, um zu suchen, und heften Sie die Einträge an,
auf die Sie immer wieder zurückgreifen. Sie erreichen ihn auch über das Zwischenablage-Symbol in der
oberen Leiste.

Der Verlauf besteht nur so lange wie Ihre Sitzung, und nur angeheftete Einträge werden gespeichert. Bevor
Sie etwas Geheimes kopieren, schalten Sie im selben Menü den **Privatmodus** ein, dann wird nichts
aufgezeichnet, bis Sie ihn wieder ausschalten.

## Das Dock

Das Dock unten enthält Ihre angehefteten Apps und die, die gerade laufen. `Alt+1` bis `Alt+9` wechseln
zur App an dieser Position und öffnen sie, falls sie nicht läuft. Klicken Sie mit der rechten Maustaste
auf eine App, um sie anzuheften oder zu lösen.

## Das Amethystora-Menü

`Super+Alt+Space` öffnet ein einziges Menü für all das, was sonst über die Einstellungen, das Terminal
und [`ame`](terminal.md#ame) verstreut ist:

| Eintrag | Funktion |
| --- | --- |
| Ask an agent | Öffnet den [KI-Agenten](ai-agent.md) |
| Diagnose a problem | Lässt den Agenten herausfinden, warum etwas kaputtgegangen ist |
| Make a widget | Lässt den Agenten ein [Widget](widgets.md) für die obere Leiste erstellen |
| Theme | Die Themenauswahl |
| Background | Die Hintergrundbilder des aktuellen Themas |
| Keybindings | Die Tastenkürzel, im Terminal |
| Manual | Dieses Handbuch |
| Web apps | Eine [Web-App](web-apps.md) installieren oder entfernen |
| Apps and system commands | Jeder `ame`-Befehl, in seiner Gruppe |
| System | Sperren, abmelden, neu starten, herunterfahren, nach Aktualisierungen suchen, der Sicherheitsbericht |

Bewegen Sie sich mit den Pfeiltasten oder tippen Sie zum Filtern, `Enter` zum Auswählen, `Esc` zum
Zurückgehen.

## Fenster kacheln

PaperWM ordnet die Fenster für Sie an. Jede Arbeitsfläche ist ein Streifen aus Fenstern, die in voller
Höhe nebeneinanderstehen, und der Streifen kann breiter sein als der Bildschirm. Ein neues Fenster öffnet
sich rechts von dem, in dem Sie sich befinden, Fenster überlappen sich nie, und der Streifen scrollt so,
dass das fokussierte Fenster sichtbar bleibt:

```
  ┌────────┬──────────────┬──────────────────────┬────────┐
  │  Mail  │   Terminal   │       Browser        │  Chat  │
  └────────┴──────────────┴──────────────────────┴────────┘
           ╰──────────── the screen ─────────────╯
```

Mail und Chat sind weiterhin offen, nur jenseits des Bildschirmrands. `Super+Left` scrollt zurück zu Mail.
Schieben Sie den Mauszeiger gegen den linken oder rechten Bildschirmrand, um zu sehen, was dahinter
liegt, und klicken Sie dort auf ein Fenster, um zu ihm zu wechseln. Auf einem Touchpad wischen Sie mit
drei Fingern, um den Streifen zu verschieben.

Die Tasten folgen einem Muster. `Super` und eine Pfeiltaste wechselt zu einem anderen Fenster. Nehmen Sie
`Ctrl` hinzu, und stattdessen bewegt sich das Fenster. Nehmen Sie `Shift` hinzu, und Sie wechseln zu
einem anderen Monitor.

### Sich bewegen

| Taste | Funktion |
| --- | --- |
| `Super+Left` / `Super+Right` | Das Fenster links / rechts |
| `Super+Up` / `Super+Down` | Das Fenster darüber / darunter, wenn sich Fenster eine Spalte teilen |
| `Super+Home` / `Super+End` | Das erste / letzte Fenster auf der Arbeitsfläche |
| `Super+[` / `Super+]` | Den Streifen verschieben, ohne das fokussierte Fenster zu wechseln |
| `Super+Shift` und eine Pfeiltaste | Der Monitor in dieser Richtung |

### Anordnen

| Taste | Funktion |
| --- | --- |
| `Super+Ctrl+Left` / `Super+Ctrl+Right` | Das Fenster entlang des Streifens nach links / rechts verschieben |
| `Super+Ctrl+Up` / `Super+Ctrl+Down` | Es in seiner Spalte nach oben / unten verschieben |
| `Super+I` | Das Fenster rechts in diese Spalte holen, unter dieses |
| `Super+O` | Das unterste Fenster dieser Spalte in eine eigene Spalte hinausschieben |
| `Super+Shift+O` | Dieses Fenster in eine eigene Spalte hinausschieben |
| `Super+Ctrl+Page Up` / `Page Down` | Es auf die vorherige / nächste Arbeitsfläche verschieben |
| `Super+Shift+Ctrl` und eine Pfeiltaste | Es auf den Monitor in dieser Richtung verschieben |
| `Super+T`, `Super` gedrückt halten | Das Fenster beim Bewegen mitnehmen und dort ablegen, wo Sie loslassen |

### Größe

| Taste | Funktion |
| --- | --- |
| `Super+R` | Die Breite schrittweise auf 38 %, 50 % und 62 % des Bildschirms setzen (`Super+Alt+R` geht zurück) |
| `Super+Shift+R` | Dasselbe für die Höhe eines Fensters in einer Spalte |
| `Super+F` | Die Bildschirmbreite ausfüllen, und zurück |
| `Super+C` | Das Fenster auf dem Bildschirm zentrieren |
| `Super+Shift+C` | Wohin der Streifen ein fokussiertes Fenster scrollt: gerade in Sicht, in die Mitte oder an den Rand |
| `Super+Shift+W` | Wo sich neue Fenster öffnen: rechts, links oder unter diesem |

### Schwebende Fenster

Dialoge schweben von selbst über dem Streifen. `Super+Ctrl+Escape` hebt das fokussierte Fenster aus dem
Streifen, sodass es ebenfalls schwebt, und setzt es wieder zurück. `Super+Alt+Escape` blendet alle auf
diese Weise schwebenden Fenster auf einmal aus und holt sie wieder zurück.

### Und der Rest

| Taste | Funktion |
| --- | --- |
| `Super+N` | Ein neues Fenster der App, in der Sie sich befinden |
| `Super+Ctrl+B` | Die obere Leiste auf dieser Arbeitsfläche aus- oder einblenden |

Die Einstellungen von PaperWM finden Sie unter **PaperWM** in der **Erweiterungsverwaltung**. Dazu gehören
die Abstände, die Breiten, durch die `Super+R` schaltet, und jede Taste, auch einige, die diese Seite
auslässt.

### Klassische Fenster

Wenn Sie lieber Fenster hätten, die frei schweben und sich überlappen, wie unter Windows und macOS,
wechseln Sie zum klassischen Layout:

```bash
ame desktop layout classic
```

Das schaltet PaperWM aus, und Aktualisierungen lassen es ausgeschaltet. Fenster öffnen sich dann dort, wo
GNOME sie platziert, und Sie ziehen sie an der Titelleiste. `Super+Up` maximiert und `Super+Down` stellt
wieder her, `Super+Left` / `Super+Right` legen ein Fenster auf diese Bildschirmhälfte, und
`Super+Shift+Left` / `Super+Shift+Right` verschieben es auf den nächsten Monitor.
`ame desktop layout tiling` bringt den Streifen zurück. Bei Ihrer ersten Anmeldung bietet eine
Benachrichtigung dieselbe Wahl an.

## Fenster

| Taste | Funktion |
| --- | --- |
| `Super+W` | Das Fenster schließen |
| `Super+Backspace` | Die Größe mit den Pfeiltasten ändern |
| `Shift+F11` | Vollbild, mit Titelleiste |
| `Super+Tab` / `Alt+Tab` | Zwischen Apps / zwischen Fenstern wechseln |

Die Knöpfe rechts in jeder Titelleiste minimieren, maximieren und schließen.

## Arbeitsflächen

Es sind immer sechs, sodass `Super+3` immer denselben Ort meint. Eine verbreitete Aufteilung: ein Browser
auf 1, ein Terminal auf 2, Chat auf 6. `Super+Shift+3` bringt das fokussierte Fenster auf Arbeitsfläche 3.
`Super+Page Up` / `Super+Page Down` wechseln zur vorherigen / nächsten Arbeitsfläche, und
`Super+Shift+Ctrl+Left` / `Super+Shift+Ctrl+Right` verschieben das Fenster auf den nächsten Monitor.

## Erweiterungen

Diese GNOME-Shell-Erweiterungen sind im Abbild enthalten:

| Erweiterung | Was sie tut |
| --- | --- |
| PaperWM | [Kacheln](#tiling-windows): Fenster nebeneinander auf einem scrollenden Streifen |
| Space Bar | Die Arbeitsflächen in der oberen Leiste |
| TopHat | Die Anzeigen für Prozessor, Speicher und Netzwerk |
| Dash to Dock | Das Dock |
| Search Light | Die Suche auf `Super+Space` |
| Fuzzy App Search | App-Suche, die Tippfehler verzeiht |
| Clipboard Indicator | Der [Verlauf der Zwischenablage](#the-clipboard) auf `Super+Shift+V` |
| Blur my Shell | Das Milchglas hinter der Leiste, der Übersicht und den Fenstern |
| Just Perfection | Schnellere Animationen und keine Einblendung beim Wechsel der Arbeitsfläche |
| AppIndicator | Statussymbole für Apps, die sie verwenden |
| Caffeine | Ein Schalter in den Schnelleinstellungen, der den Bildschirm wach hält |
| GSConnect | Ihr Android-Telefon: Benachrichtigungen, Dateien, Zwischenablage, SMS |
| Logo Menu | Das Amethystora-Logo oben links: Verknüpfungen zu Systemwerkzeugen |
| Gradia | Ein Bildschirmfoto direkt nach der Aufnahme beschriften |
| Bazaar integration | Verbindet die Shell mit Bazaar, dem Software-Center |

Schalten Sie jede davon in der **Erweiterungsverwaltung** aus oder ändern Sie dort ihre Einstellungen.
Eines sollten Sie wissen: Nach jeder Aktualisierung des Abbilds werden die eigenen Erweiterungen des
Abbilds wieder eingeschaltet, damit eine, die versehentlich oder durch einen Absturz ausgeschaltet wurde,
nicht für immer aus bleibt. Das Ausschalten einer Erweiterung hält bis zur nächsten Aktualisierung. Die
Ausnahme ist PaperWM unter dem [klassischen Layout](#classic-windows), das ausgeschaltet bleibt.

## Dateien

`Super+Shift+F` öffnet ein Fenster von Dateien und `Super+E` Ihren persönlichen Ordner. Ordner öffnen
sich als Raster, in dem die Ordnersymbole des Symbolthemas ganz zur Geltung kommen.
