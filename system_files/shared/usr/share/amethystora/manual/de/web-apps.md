# Web-Apps

Viele der Apps, die Sie nutzen, sind Websites: E-Mail, Chat, Musik, ein Kalender. Eine Web-App bringt
eine davon in ein eigenes Fenster, ohne Reiter oder Adressleiste, mit eigenem Symbol in der
Anwendungsübersicht und im Dock und einem eigenen Platz in `Alt+Tab`.

## Eine installieren

Wählen Sie im Amethystora-Menü (`Super+Alt+Space`) **Web apps**, dann **Install a web app**, und
beantworten Sie drei Fragen: einen Namen, die Adresse und ein Symbol. Lassen Sie das Symbol leer, wird das
eigene Symbol der Website geladen. Dasselbe in einem Terminal:

```bash
amethystora-webapp install "Proton Mail" mail.proton.me
amethystora-webapp install "Calendar" https://calendar.proton.me ~/Pictures/calendar.png
```

Das Symbol kann ein Bild im Web sein, eine Datei oder der Name eines Symbols aus dem Symbolthema.

## Öffnen, anheften, entfernen

Eine Web-App steht wie jede andere App in der Anwendungsübersicht: Suchen Sie sie mit `Super+Space`, und
klicken Sie sie im Dock mit der rechten Maustaste an, um sie anzuheften. Um eine zu entfernen, wählen Sie
im selben Menü **Remove a web app** oder:

```bash
amethystora-webapp remove "Proton Mail"
```

Um eine Website nur einmal als Web-App zu öffnen, ohne sie zu installieren: `amethystora-webapp <address>`.

## Welcher Browser sie ausführt

Web-Apps öffnen sich in Ihrem Standardbrowser, der Firefox ist, bis Sie einen anderen wählen, und folgen
Ihnen, wenn Sie ihn wechseln. Nur `http`- und `https`-Adressen können zu Web-Apps werden.

| Standardbrowser | Wie sich eine Web-App öffnet |
| --- | --- |
| Brave, Chrome, Chromium, Edge, Vivaldi oder Opera | Im eigenen App-Fenster des Browsers. Sie teilt die Anmeldungen, Passwörter und Erweiterungen des Browsers. |
| Firefox, LibreWolf, Zen, Floorp oder Waterfox | In einem Fenster ohne Reiter oder Werkzeugleiste, mit einem eigenen Profil. Firefox hat kein App-Fenster, daher behält jede Web-App ihre eigenen Anmeldungen und sieht die des Browsers nicht. |
| Jeder andere | In einem Browser aus den beiden Zeilen darüber: einem auf Chromium basierenden, wenn Sie einen installiert haben, sonst Firefox. |

Das Profil einer Firefox-Web-App liegt in `~/.local/share/amethystora-webapp` oder, wenn der Browser ein
Flatpak ist, im Ordner des Browsers unter `~/.var/app`. Das Entfernen der Web-App löscht es, samt
Anmeldungen.
