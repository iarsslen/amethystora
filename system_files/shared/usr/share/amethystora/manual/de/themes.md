# Themen

Ein Thema ist eine einzige Palette, und alles wird aus ihr gemalt. Wechseln Sie das Thema, und der ganze
Desktop ändert sich gemeinsam: GNOMEs heller oder dunkler Stil und die Akzentfarbe, das Terminal, der
Shell-Prompt, die obere Leiste, das Dock, das Hintergrundbild, VSCodium und dieses Handbuch. Ein helles
Thema gibt dem Dock eine leichte dunkle Tönung, damit seine Symbole auch auf einem blassen
Hintergrundbild hervortreten.

## Wechseln

| Taste | Funktion |
| --- | --- |
| `Super+Ctrl+Shift+Space` | Ein Thema wählen |
| `Super+Ctrl+D` | Zwischen der hellen und der dunklen Version des Themas wechseln |
| `Super+Ctrl+Space` | Nächstes Hintergrundbild des aktuellen Themas |

Dasselbe in einem Terminal:

```bash
ame desktop theme                   # pick one from a list
amethystora-theme list              # the themes, with the current one marked
amethystora-theme set "Tokyo Night" # apply one by name
amethystora-theme toggle            # light or dark
amethystora-theme current           # which one is on
```

## Die Themen

| Thema | Zu verwendender Name | Stil |
| --- | --- | --- |
| Amethystora | `amethystora` | Dunkel, die Vorgabe |
| Amethystora Light | `amethystora-light` | Hell |
| Catppuccin Mocha | `catppuccin` | Dunkel |
| Catppuccin Latte | `catppuccin-latte` | Hell |
| Everforest | `everforest` | Dunkel |
| Gruvbox | `gruvbox` | Dunkel |
| Matte Black | `matte-black` | Dunkel |
| Nord | `nord` | Dunkel |
| Rosé Pine Dawn | `rose-pine-dawn` | Hell |
| Tokyo Night | `tokyo-night` | Dunkel |

Die beiden Amethystora-Themen bringen auch das GTK-Thema von Amethystora mit, das mit den drei farbigen
Lichtern in der Ecke jedes Fensters. Die anderen behalten GNOMEs eigenes Aussehen in ihrer Akzentfarbe.
`Super+Ctrl+D` wechselt ein Thema zu seinem Partner (Catppuccin Mocha und Latte, Amethystora und
Amethystora Light); ein Thema ohne Partner wechselt zu Amethystora im jeweils anderen Modus.

## Hintergrundbilder

Jedes Thema bringt drei Hintergrundbilder erfundener Orte mit, gemalt in seinen eigenen Farben, und der
Wechsel zu einem Thema legt dessen erstes auf den Desktop: eine Neonstadt im Regen für Tokyo Night, ein
Polarlicht über einem Bergsee für Nord, Kiefern im Nebel für Everforest, ein Sonnenuntergang in der Wüste
für Gruvbox, Gipfel unter einem Pastellmond für Catppuccin, eine Finsternis für Matte Black und so weiter.
`Super+Ctrl+Space` schaltet durch sie hindurch. Die beiden Amethystora-Themen beginnen mit den Facetten
eines geschliffenen Steins und haben außerdem das Kristallfeld und einen Nachthimmel aus violettem Rauch;
GNOMEs Einstellungen bieten diese unter „Darstellung“ an.

Um eigene hinzuzufügen, legen Sie Bilder (JPG, PNG, WebP oder SVG) in einen Ordner, der nach dem Thema
benannt ist. Sie folgen auf die eigenen Bilder des Themas:

```bash
mkdir -p ~/.config/amethystora/backgrounds/amethystora
cp ~/Pictures/mountains.jpg ~/.config/amethystora/backgrounds/amethystora/
```

`amethystora-theme bg list` zeigt, durch welche Bilder das aktuelle Thema schaltet, und
`amethystora-theme bg set <picture>` setzt eines direkt.

## Übergänge

Ein neues Thema oder Hintergrundbild erscheint nicht einfach. Der Bildschirm hält einen Moment still,
während sich darunter alles ändert, dann öffnet sich der neue Desktop in einem Kreis vom Mauszeiger aus,
mit einem Leuchten in der Akzentfarbe des Themas entlang des Randes. Es funktioniert gleich, egal auf
welchem Weg Sie die Änderung vornehmen: mit den Tasten oben, in GNOMEs Einstellungen oder mit dem Knopf
„Dunkler Stil“ in den Schnelleinstellungen.

```bash
ame desktop transition         # pick one from a list
ame desktop transition wave    # or name it
```

| Übergang | Sieht aus wie |
| --- | --- |
| `grow` | Ein Kreis öffnet sich vom Mauszeiger aus. Die Vorgabe |
| `outer` | Der neue Desktop schließt sich von den Rändern her um den Mauszeiger |
| `wipe` | Eine weiche Kante wischt schräg über den Bildschirm |
| `wave` | Dasselbe, mit einer welligen Kante |
| `fade` | Eine einfache Überblendung |
| `random` | Einer der ersten vier, in einem beliebigen Winkel |
| `none` | Keine Animation: Das Hintergrundbild blendet über, wie GNOME es überblendet |

Ein Übergang dauert 1,2 Sekunden. Um das zu ändern, geben Sie die Dauer in Millisekunden an:

```bash
gsettings set org.gnome.shell.extensions.amethystora-transitions duration 800
```

Solange Animationen in den Einstellungen unter Barrierefreiheit ausgeschaltet sind, gibt es keine
Übergänge. Sie stammen von der Erweiterung Amethystora Transitions, die sich in der
Erweiterungsverwaltung ausschalten lässt.

## Symbole

Die Symbole sind candy-icons, derselbe Satz unter jedem Thema: seine Ordner, seine Dateitypen und seine
Piktogramme mit Farbverlauf für die Apps, die eine schlichte Aufgabe erfüllen, etwa Dateien,
Einstellungen oder der Taschenrechner. Eine App mit eigenem Logo behält es. Firefox, Thunderbird, eine
JetBrains-IDE und das meiste, was Sie installieren, zeigen das Symbol, das ihr Hersteller gezeichnet hat,
kein nachgezeichnetes: Ein Logo ist eine Marke, und wie es aussieht, entscheidet sein Inhaber. Deshalb
mischt das Dock die beiden Stile.

## Ein Thema ändern oder ein eigenes erstellen

Themen werden schreibgeschützt in `/usr/share/amethystora/themes` ausgeliefert. Ein gleichnamiger Ordner
in `~/.config/amethystora/themes` wird darübergelegt, sodass Sie nur die Dateien schreiben, die Sie ändern
möchten. Ein Ordner mit eigenem Namen ist ein neues Thema. Jede Datei ist klein und optional, außer der
Palette:

| Datei | Enthält |
| --- | --- |
| `colors.toml` | Die Palette: `accent`, `foreground`, `background`, `cursor`, `selection_foreground`, `selection_background` und `color0` bis `color15` |
| `light.mode` | Vorhanden und leer, wenn das Thema hell ist |
| `pair.theme` | Das Thema, zu dem `Super+Ctrl+D` wechselt |
| `accent.theme` | GNOMEs Akzentfarbe: blue, teal, green, yellow, orange, red, pink, purple oder slate. Ohne sie wird die nächstliegende gewählt |
| `gtk.theme` | Der Name eines GTK-Themas, statt GNOMEs eigenem Aussehen |
| `icons.theme` | Ein Symbolthema, statt candy-icons |
| `cursor.theme` | Ein Zeigerthema |
| `vscode.theme` | Das Farbthema von VSCodium, zu dem gewechselt wird |
| `tophat.theme` | Die Farbe der Anzeigen in der oberen Leiste, wenn die Akzentfarbe als dünne Linie schlecht lesbar ist |
| `backgrounds/` | Hintergrundbilder |
| `backgrounds.list` | Hintergrundbilder, die anderswo im System liegen, ein Pfad pro Zeile. Das erste ist das, mit dem das Thema beginnt |

Ein Thema ohne eigene Bilder bekommt vier, die in seinen Farben gezeichnet werden: ein sanftes Leuchten,
Hügel im Dunst, eine Höhenlinienkarte und fließende Bänder.

Ein eigenes Thema braucht drei Befehle:

```bash
mkdir -p ~/.config/amethystora/themes/sunset
cp /usr/share/amethystora/themes/amethystora/colors.toml ~/.config/amethystora/themes/sunset/
amethystora-theme set sunset
```

Bearbeiten Sie die Farben, führen Sie `amethystora-theme set sunset` erneut aus und sehen Sie sich das
Ergebnis an.

## Weiterführendes

- **Wie eine Konfiguration geschrieben wird.** Die Terminalpalette, der Prompt, die Farben von btop und
  die gezeichneten Hintergrundbilder sind Vorlagen in `/usr/share/amethystora/themed`. Kopieren Sie eine
  nach `~/.config/amethystora/themed/` und bearbeiten Sie die Kopie, um zu ändern, wie jedes Thema sie
  darstellt.
- **Bei jedem Wechsel etwas ausführen.** Legen Sie eine ausführbare Datei in
  `~/.config/amethystora/hooks/theme-set.d/`. Sie erhält den Namen des Themas in `AMETHYSTORA_THEME` und
  seinen Ordner in `AMETHYSTORA_THEME_DIR`.
- **Ihr eigener Prompt bleibt Ihrer.** Wenn Sie `~/.config/starship.toml` selbst geschrieben haben, lässt
  das Thema ihn in Ruhe.
- **Bearbeiten Sie nie `~/.config/amethystora/current/`.** Es wird bei jedem Wechsel neu geschrieben.

## Das Bootmenü

Auch das Bootmenü kann die Amethystora-Grafik tragen. Standardmäßig ist das ausgeschaltet, weil das
Bootmenü außerhalb des Abbilds liegt:

```bash
ame desktop boot-menu
```

Führen Sie den Befehl erneut aus, um die Grafik wieder zu entfernen. Sobald sie eingeschaltet ist, halten
Aktualisierungen des Abbilds sie auf dem neuesten Stand.
