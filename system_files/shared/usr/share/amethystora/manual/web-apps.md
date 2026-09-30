# Web apps

Plenty of the apps you use are websites: mail, chat, music, a calendar. A web app puts one in a
window of its own, with no tabs or address bar, its own icon in the app grid and the dock, and its
own place in `Alt+Tab`.

## Install one

From the Amethystora menu (`Super+Alt+Space`), choose **Web apps**, then **Install a web app**, and
answer three questions: a name, the address, and an icon. Leave the icon empty and the site's own is
fetched. The same from a terminal:

```bash
amethystora-webapp install "Proton Mail" mail.proton.me
amethystora-webapp install "Calendar" https://calendar.proton.me ~/Pictures/calendar.png
```

The icon can be a picture on the web, a file, or the name of an icon from the icon theme.

## Open, pin, remove

A web app is in the app grid like any other app: search for it with `Super+Space`, and right-click it
in the dock to pin it. To remove one, choose **Remove a web app** from the same menu, or:

```bash
amethystora-webapp remove "Proton Mail"
```

To open a site as a web app just once, without installing it: `amethystora-webapp <address>`.

## Which browser runs them

Web apps open in your default browser when it is Chromium-based (Brave, Chrome, Chromium, Edge,
Vivaldi or Opera), and in Brave otherwise. They share that browser's sign-ins, passwords and
extensions. Only `http` and `https` addresses can become web apps.
