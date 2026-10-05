# Notizen und Aufgaben

**Notizen** in der Anwendungsübersicht bewahrt Ihre Notizen und Ihre To-do-Listen in einem einzigen
Fenster auf. Alles bleibt auf diesem Rechner. Nichts wird synchronisiert, und die App verbindet sich nie
mit dem Internet. Sie ersetzt Joplin und Planify und übernimmt, was Sie dort bereits haben (siehe
[Von Joplin oder Planify umsteigen](#coming-from-joplin-or-planify)).

Beim ersten Öffnen bietet sie an, Ihre Notizen mit einer Passphrase zu verschlüsseln. Diese Wahl empfiehlt
sie, und der Rest dieser Seite geht davon aus, dass Sie sie getroffen haben.

## Notizen

Notizen werden in Markdown geschrieben und liegen in Notizbüchern, die weitere Notizbücher enthalten
können. Der Editor zeigt den Text und die formatierte Notiz nebeneinander. **Ctrl+E** wechselt zwischen
dem Text, beidem und der formatierten Notiz allein.

- **Checklisten:** `- [ ] like this`. Haken Sie die Kästchen in der formatierten Notiz ab.
- **Anhänge:** Fügen Sie ein Bild ein, ziehen Sie eine Datei auf die Notiz oder verwenden Sie die
  Büroklammer. Bilder werden in der Notiz angezeigt. Klicken Sie auf einen anderen Anhang, um eine Kopie
  zu speichern.
- **Schlagwörter:** Tippen Sie in die Schlagwortzeile unter dem Titel und drücken Sie **Enter**.
  Schlagwörter werden in der Seitenleiste aufgeführt.
- **Eine Notiz verschieben:** Wählen Sie oben in der Notiz ein anderes Notizbuch, oder ziehen Sie die
  Notiz auf ein Notizbuch in der Seitenleiste.
- **Frühere Versionen:** die Uhr oben in einer Notiz. Jedes Mal, wenn Sie eine Notiz nach zehn Minuten
  Pause wieder bearbeiten, wird eine Version aufbewahrt, bis zu den letzten 30. Wenn Sie eine
  wiederherstellen, bleibt der Text, den sie ersetzt, ebenfalls als Version erhalten.
- **Papierkorb:** Eine Notiz, die Sie löschen, kommt in den Papierkorb, wo Sie sie wiederherstellen oder
  endgültig löschen können.
- **PDF:** Das Menü **⋯** einer Notiz exportiert sie als PDF.

## Aufgaben

**Aufgaben** oben in der Seitenleiste wechselt zu Ihren To-do-Listen:

| Ansicht | Zeigt |
| --- | --- |
| Eingang | Aufgaben, die in keinem Projekt sind |
| Heute | Was heute fällig ist, und alles Überfällige |
| Demnächst | Die kommende Woche, Tag für Tag, und alles danach |
| Angeheftet | Die Aufgaben, die Sie angeheftet haben |
| Erledigt | Was Sie erledigt haben, das Neueste zuerst |

Projekte gruppieren Aufgaben und lassen sich in Abschnitte unterteilen. Labels gelten projektübergreifend.
Klicken Sie auf eine Aufgabe, um Datum und Uhrzeit, Wiederholung, Erinnerung, Priorität, Labels und
Notizen festzulegen und Unteraufgaben hinzuzufügen.

Das Feld **Aufgabe hinzufügen** versteht ein wenig Alltagssprache, allerdings auf Englisch. Es nimmt
Folgendes aus dem Titel heraus:

| Eingabe | Für |
| --- | --- |
| `today`, `tomorrow`, `friday`, `next week`, `2026-10-31` | Das Datum |
| `5pm`, `17:30` | Die Uhrzeit, mit einer Erinnerung zu dieser Zeit |
| `every day`, `every 2 weeks`, `monthly` | Eine Aufgabe, die sich wiederholt |
| `p1` bis `p4` | Die Priorität, `p1` die höchste |
| `@errand` | Ein Label, das angelegt wird, falls es neu ist |
| `#Garden` | Ein vorhandenes Projekt |

Wenn Sie eine sich wiederholende Aufgabe erledigen, rückt sie auf ihr nächstes Datum vor.

### Erinnerungen

Eine Aufgabe mit Uhrzeit kann Sie erinnern, von **Zum Zeitpunkt** bis **1 Tag vorher**. Erinnerungen
erscheinen als Benachrichtigungen, während Notizen läuft. Wenn Sie das Fenster schließen, läuft Notizen im
Hintergrund weiter, bis die anstehenden Erinnerungen ausgelöst wurden. Das können Sie in den
**Einstellungen** ausschalten. Ihre Notizen sind gesperrt, während die App so läuft; nur die Titel und
Zeiten der Erinnerungen werden im Arbeitsspeicher behalten.

## Verschlüsselung

Bei eingeschalteter Verschlüsselung werden Ihre Notizen, Aufgaben und Anhänge mit AES-256-GCM
verschlüsselt auf die Festplatte geschrieben, mit einem zufälligen Schlüssel, den nur Ihre Passphrase
oder ein [Passkey](#passkeys), den Sie hinzufügen, öffnen kann. Die Passphrase wird mit scrypt gestreckt,
was für jeden Rateversuch 128 MiB Speicher kostet, sodass das Durchprobieren von Passphrasen langsam ist.

Sie bleibt auch gegen Quantencomputer sicher. Was ein Quantencomputer bricht, ist
Public-Key-Kryptografie (RSA, elliptische Kurven), und davon wird hier keine verwendet. Gegen eine
Chiffre wie AES kann ein Quantencomputer bestenfalls die Schlüssellänge halbieren. Damit behält AES-256
eine Stärke von 128 Bit, weshalb NIST und die CNSA 2.0 der NSA AES-256 für die Zeit nach dem Aufkommen
von Quantencomputern beibehalten.

> **Niemand kann eine vergessene Passphrase wiederherstellen.** Nicht Amethystora, kein Administrator,
> niemand. Bewahren Sie sie an einem sicheren Ort auf, und halten Sie eine [Sicherung](#backing-up) bereit.

Ihre Notizen werden gesperrt:

- nach 10 Minuten ohne Nutzung von Notizen (**Einstellungen**, **Bei Abwesenheit sperren**),
- wenn der Bildschirm gesperrt wird, der Rechner in Bereitschaft geht oder das Fenster geschlossen wird,
- wenn Sie **Ctrl+L** drücken oder **Sperren** in der Seitenleiste wählen.

In den **Einstellungen** ändern Sie auch die Passphrase und schalten die Verschlüsselung aus oder wieder
ein.

### Passkeys

Ein FIDO2-Sicherheitsschlüssel (YubiKey, Thetis oder ein Modell mit Fingerabdruck wie der YubiKey Bio)
kann Ihre Notizen öffnen, sodass Sie die Passphrase nicht jedes Mal eingeben müssen. Die Passphrase
funktioniert weiterhin, und sie öffnet Ihre Notizen, wenn der Schlüssel verloren geht: Ein Passkey ist ein
zweiter Zugang, nie der einzige.

Um einen hinzuzufügen, stecken Sie den Schlüssel ein, öffnen die **Einstellungen** und wählen **Passkey
hinzufügen**. Geben Sie Ihre Passphrase und die PIN des Schlüssels ein, oder lassen Sie die PIN bei einem
Schlüssel, der Ihren Fingerabdruck liest, leer. Der Schlüssel blinkt zweimal; berühren Sie ihn jedes Mal.
Danach bietet der Sperrbildschirm **Mit Passkey öffnen** an, was nach der PIN des Schlüssels oder Ihrem
Fingerabdruck und einer Berührung fragt.

- **Der Schlüssel braucht eine PIN**, und ein Modell mit Fingerabdruck einen registrierten Finger. Legen
  Sie beides in Firefox unter `about:webauthn` fest. Eine Berührung allein öffnet Ihre Notizen nie: Wer
  den Schlüssel findet, kann ihn ohne die PIN oder Ihren Finger nicht benutzen, und der Schlüssel sperrt
  seine PIN nach acht Fehlversuchen.
- **Fügen Sie einen zweiten Schlüssel als Ersatz hinzu**, einen nach dem anderen. Jeder wird in den
  **Einstellungen** aufgeführt, wo **Entfernen** ihm das Öffnen Ihrer Notizen wieder entzieht.
- **Wenn ein Schlüssel verloren geht**, entfernen Sie ihn. Wer den Schlüssel besitzt, seine PIN kennt und
  eine ältere Kopie Ihres Notizenordners hat, könnte diese Kopie noch öffnen. Wenn Sie die
  Verschlüsselung aus- und wieder einschalten, bekommen Ihre Notizen einen neuen Schlüssel, den kein
  entfernter Passkey öffnet; fügen Sie danach die Schlüssel, die Sie noch haben, erneut hinzu.
- Eine [Sicherung](#backing-up) fragt immer nach der Passphrase: Passkeys sind nicht Teil davon.

Der Schlüssel speichert nichts von Ihren Notizen. Er enthält ein Geheimnis, das ihn nie verlässt, und
berechnet nach geprüfter PIN oder geprüftem Fingerabdruck einen Wert (HMAC-SHA256, das `hmac-secret` von
FIDO2), mit dem eine zweite Kopie des Schlüssels Ihrer Notizen verschlüsselt ist. Was auf der Festplatte
liegt, ist weiterhin allein mit AES-256 verschlüsselt.

## Sichern

Da nichts synchronisiert wird, bewahren Sie eine Kopie woanders auf. In den **Einstellungen**:

- **In eine Datei sichern** schreibt eine `.amnotes`-Datei mit allem darin, Anhänge eingeschlossen,
  verschlüsselt wie Ihre Notizen. Sie lässt sich mit der Passphrase, die Sie beim Erstellen hatten, auf
  jedem Rechner öffnen: Wählen Sie sie unter **Importieren** aus.
- **Als Markdown exportieren** schreibt jede Notiz als Markdown-Datei in einen Ordner pro Notizbuch und
  jedes Projekt als Checkliste. Diese Dateien sind **nicht** verschlüsselt.

Ihre Notizen selbst liegen in `~/.local/share/amethystora-notes`.

## Von Joplin oder Planify umsteigen

Öffnen Sie die **Einstellungen** und verwenden Sie **Importieren**. Wenn Sie dieselbe Datei erneut
importieren, wird aktualisiert, was aus ihr stammt, statt es doppelt hinzuzufügen.

- **Joplin:** Wählen Sie in Joplin **Datei**, **Alles exportieren**, **JEX**. Importieren Sie die
  `.jex`-Datei. Notizbücher, Notizen, Schlagwörter und Anhänge werden übernommen. Die To-dos von Joplin
  werden zu Aufgaben im Eingang.
- **Planify:** Öffnen Sie in Planify **Einstellungen**, **Sicherung**, und erstellen Sie eine Sicherung.
  Importieren Sie deren `.json`-Datei aus
  `~/.var/app/io.github.alainm23.planify/data/io.github.alainm23.planify/backups`. Projekte, Abschnitte,
  Aufgaben, Unteraufgaben, Labels, Daten und Wiederholungen werden übernommen.
- **Markdown-Dateien** kommen in ein Notizbuch namens **Imported**.

Sobald alles übernommen ist, können Sie die alten Apps in Bazaar entfernen oder mit
`flatpak uninstall net.cozic.joplin_desktop io.github.alainm23.planify`.

## Tasten

| Taste | Funktion |
| --- | --- |
| **Ctrl+N** | Eine neue Notiz, oder eine neue Aufgabe in **Aufgaben** |
| **Ctrl+F** | Notizen oder Aufgaben durchsuchen |
| **Ctrl+1** / **Ctrl+2** | Notizen / Aufgaben |
| **Ctrl+E** | Text, beides oder die formatierte Notiz |
| **Ctrl+B**, **Ctrl+I**, **Ctrl+K** | Fett, kursiv, Link |
| **Ctrl+L** | Sperren |
| **Ctrl+,** | Einstellungen |
