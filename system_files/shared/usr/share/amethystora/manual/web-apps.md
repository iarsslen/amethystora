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

Web apps open in your default browser, and follow you when you change it. Only `http` and `https`
addresses can become web apps.

| Default browser | How a web app opens |
| --- | --- |
| Brave, Chrome, Chromium, Edge, Vivaldi or Opera | In the browser's own app window. It shares the browser's sign-ins, passwords and extensions. |
| Firefox, LibreWolf, Zen, Floorp or Waterfox | In a window without tabs or toolbar, on a profile of its own. Firefox has no app window, so each web app keeps its own sign-ins and does not see the browser's. |
| Any other | In the first browser of the two rows above that is installed, which is Brave unless you removed it. With none, the site opens as a link does. |

A Firefox web app's profile is in `~/.local/share/amethystora-webapp`, or in the browser's folder
under `~/.var/app` when the browser is a Flatpak. Removing the web app deletes it, sign-ins included.
