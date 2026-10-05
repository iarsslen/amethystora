# Widgets

Die obere Leiste kann Eigenes anzeigen: einen Fokus-Timer, das Wetter, ungelesene E-Mails, ob das VPN
verbunden ist, wie viele Pull-Requests auf Ihre Überprüfung warten. Jedes davon ist ein *Widget*, ein
kleines Programm, dessen Ausgabe die Leiste in eine Beschriftung, ein Symbol und ein Menü verwandelt. Sie
müssen es nicht selbst schreiben: Das erledigt der [KI-Agent](ai-agent.md).

## Den Agenten um eines bitten

Wählen Sie **Make a widget** im Amethystora-Menü (`Super+Alt+Space`) und sagen Sie, was es zeigen soll,
oder führen Sie aus:

```bash
amethystora-widgets make "a pomodoro timer"
amethystora-widgets make "how many pull requests wait for my review on GitHub"
amethystora-widgets make                          # the agent asks you what you want
```

Der Agent schreibt das Widget, prüft es, und es erscheint in der Leiste, sobald es gespeichert ist, ohne
dass Sie sich abmelden müssen. Bitten Sie auf dieselbe Weise um Änderungen: „Lass das Wetter-Widget auch
das Wetter von morgen zeigen“.

Wenn ein Widget nicht mehr funktioniert, zeigt die Leiste an seiner Stelle ein Warnzeichen. Klicken Sie
darauf, um zu lesen, was schiefgegangen ist; **Fix it with the AI agent** übergibt das Problem dem Agenten.

## Befehle

| Befehl | Funktion |
| --- | --- |
| `amethystora-widgets` | Listet Ihre Widgets auf und welche eingeschaltet sind |
| `amethystora-widgets make ["<idea>"]` | Lässt den Agenten eines erstellen |
| `amethystora-widgets new <name> [<example>]` | Beginnt eines aus einem Beispiel: `hello`, `pomodoro` oder `do-not-disturb` |
| `amethystora-widgets run <name>` | Führt es einmal so aus, wie die Leiste es tut, und sagt, was daran falsch ist |
| `amethystora-widgets fix <name> ["<what is wrong>"]` | Lässt den Agenten herausfinden, warum es fehlschlägt, und es reparieren |
| `amethystora-widgets off <name>` und `on <name>` | Blendet es in der Leiste aus oder wieder ein |
| `amethystora-widgets remove <name>` | Verschiebt es in den Papierkorb |
| `amethystora-widgets restart` | Beendet und startet jedes Widget neu |

`ame desktop widgets` führt dieselben Befehle aus.

## Selbst eines erstellen

Ein Widget ist ein Ordner in `~/.config/amethystora/widgets` mit einer `widget.json`, die einen Befehl
nennt und angibt, wie oft er ausgeführt werden soll, und dem Befehl selbst, meist einem kurzen Skript. Das
Skript gibt eine Zeile aus, die die Leiste anzeigt: einfachen Text oder JSON mit einem Symbol, einer Farbe
aus dem Thema und einem Menü, dessen Einträge Befehle ausführen, Links öffnen oder Schalter umlegen.

`amethystora-widgets new mywidget` kopiert das Beispiel `hello` als Ausgangspunkt an seinen Platz, und
`amethystora-widgets run mywidget` prüft es nach jeder Änderung. Das vollständige Format beschreibt die
eigene Anleitung des Agenten dazu, `/usr/share/amethystora/agents/skills/amethystora-widgets/SKILL.md`;
die Beispiele liegen in `/usr/share/amethystora/widgets/examples`.

## Sicherheit

Ein Widget läuft als Sie, mit Zugriff auf Ihre Dateien, wie jedes Programm, das Sie starten. Behalten Sie
nur Widgets, die Sie gelesen oder beim Agenten in Auftrag gegeben haben, und lesen Sie, was der Agent
vorschlägt, bevor Sie zustimmen, denn er fragt, bevor er etwas schreibt.

Widgets laufen außerhalb der GNOME Shell, sodass ein kaputtes oder langsames Widget ein Warnzeichen zeigt,
statt den Desktop einzufrieren oder Ihre Sitzung zu beenden. Sie halten an, während der Bildschirm
gesperrt ist.
