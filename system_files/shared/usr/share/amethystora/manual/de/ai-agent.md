# Der KI-Agent

`Super+Ctrl+Shift+A` öffnet einen KI-Agenten in einem Terminal: standardmäßig Claude Code, oder Opencode,
wenn Sie das bevorzugen. Er bringt einen Skill mit, der ihm dieses System erklärt, sodass er weiß, welche
Dateien zum Abbild gehören und welche Sie ändern dürfen, wie Themen und Tastenkürzel funktionieren, wie
Software auf einem abbildbasierten System installiert wird und was er Sie fragen muss, bevor er etwas
anrührt.

Fragen Sie ihn in Alltagssprache:

- „Mach die Symbole im Dock kleiner.“
- „Warum läuft der Lüfter meines Laptops ständig?“
- „Richte ein Python-Projekt mit uv in ~/code/scraper ein.“
- „Füge ein Tastenkürzel hinzu, das Mission Center öffnet.“
- „Erstelle ein Widget für die obere Leiste, das das Wetter anzeigt.“ Siehe [Widgets](widgets.md).

Er startet in seinem normalen Modus, fragt also, bevor er einen Befehl ausführt oder eine Datei ändert.
Lesen Sie, was er vorschlägt, bevor Sie zustimmen.

## Ein Problem diagnostizieren

**Diagnose a problem** im Amethystora-Menü (`Super+Alt+Space`) übergibt dem Agenten etwas, das
schiefgegangen ist: einen Absturz, einen fehlgeschlagenen Dienst oder Ihre eigene Beschreibung („WLAN
bricht nach dem Ruhezustand ab“). Er untersucht die Protokolle und Absturzberichte, ändert nichts und
meldet sich mit der Ursache und einem Lösungsvorschlag zurück.

```bash
amethystora-agent diagnose                       # look for anything that failed recently
amethystora-agent diagnose "wifi drops after suspend"
amethystora-agent diagnose NetworkManager.service
amethystora-agent diagnose 4242                  # a process ID
```

Die Apps übergeben ihm, was schiefgegangen ist, dort, wo Sie es schiefgehen sehen: **Den Agenten fragen,
warum** in **Aktualisierungen**, wenn eine Aktualisierung nicht abgeschlossen wurde, **Den Agenten fragen**
in **Sicherheit** neben allem, was Ihre Aufmerksamkeit braucht, und **Den Agenten fragen** in
**Protokolle** neben einem Absturz oder etwas, das ein Dienst geschrieben hat. Sie geben nur den Dienst,
die Prozessnummer oder den Wortlaut des Berichts weiter, und den Rest liest der Agent selbst. Solange die
Agentenfunktionen ausgeschaltet sind, fehlen diese Knöpfe.

## Befehle

| Befehl | Funktion |
| --- | --- |
| `amethystora-agent` | Den Agenten öffnen (dasselbe wie `Super+Ctrl+Shift+A`) |
| `amethystora-agent ask "<question>"` | Ihn mit einer ersten Frage öffnen |
| `amethystora-agent diagnose [...]` | Herausfinden, warum etwas kaputtgegangen ist, ohne etwas zu ändern |
| `amethystora-agent use claude` oder `use opencode` | Den Agenten wählen |
| `amethystora-agent install` | Den gewählten Agenten vorab installieren; auch `ame agent install` |
| `ame agent toggle` | Die Agentenfunktionen ausschalten oder wieder einschalten |

## Installieren und aktualisieren

Die Agenten sind nicht Teil des Abbilds, weil sie viel öfter neue Versionen veröffentlichen als das
Abbild. Wenn Sie einen zum ersten Mal öffnen, bietet er an, sich mit dem eigenen Installationsprogramm
seines Herstellers in Ihren persönlichen Ordner zu installieren. Von da an aktualisiert er sich selbst,
wann Sie es entscheiden: `claude update` oder `opencode upgrade`. Claude Code wird aus seinem stabilen
Kanal installiert, einer etwa eine Woche alten Version. Weil er in Ihrem persönlichen Ordner liegt,
funktioniert dieselbe Kopie auch in jeder Toolbox und jeder Distrobox.

## Datenschutz und Ausschalten

Keiner der Agenten tut etwas, bevor Sie sich bei ihm anmelden, und was Sie ihm senden, geht an den
Anbieter, bei dem Sie sich angemeldet haben. `ame agent toggle` entfernt die Menüeinträge, deaktiviert das
Tastenkürzel und entfernt die Verknüpfung zum Skill; ein Agent, den Sie installiert haben, bleibt in jedem
Fall installiert.
