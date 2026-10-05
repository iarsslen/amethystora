# Aplicaciones web

Muchas de las aplicaciones que usa son sitios web: el correo, el chat, la música, un calendario. Una
aplicación web pone uno de ellos en una ventana propia, sin pestañas ni barra de direcciones, con su
propio icono en la cuadrícula de aplicaciones y en el dock, y su propio lugar en `Alt+Tab`.

## Instalar una

En el menú de Amethystora (`Super+Alt+Space`), elija **Web apps**, luego **Install a web app**, y
responda a tres preguntas: un nombre, la dirección y un icono. Si deja el icono vacío, se descarga el
del propio sitio. Lo mismo desde una terminal:

```bash
amethystora-webapp install "Proton Mail" mail.proton.me
amethystora-webapp install "Calendar" https://calendar.proton.me ~/Pictures/calendar.png
```

El icono puede ser una imagen de la web, un archivo o el nombre de un icono del tema de iconos.

## Abrir, anclar, quitar

Una aplicación web está en la cuadrícula de aplicaciones como cualquier otra: búsquela con
`Super+Space` y pulse con el botón derecho sobre ella en el dock para anclarla. Para quitar una, elija
**Remove a web app** en el mismo menú, o:

```bash
amethystora-webapp remove "Proton Mail"
```

Para abrir un sitio como aplicación web una sola vez, sin instalarlo: `amethystora-webapp <address>`.

## Qué navegador las ejecuta

Las aplicaciones web se abren en su navegador predeterminado, que es Firefox hasta que elija otro, y
le siguen cuando lo cambia. Solo las direcciones `http` y `https` pueden convertirse en aplicaciones
web.

| Navegador predeterminado | Cómo se abre una aplicación web |
| --- | --- |
| Brave, Chrome, Chromium, Edge, Vivaldi u Opera | En la propia ventana de aplicación del navegador. Comparte los inicios de sesión, las contraseñas y las extensiones del navegador. |
| Firefox, LibreWolf, Zen, Floorp o Waterfox | En una ventana sin pestañas ni barra de herramientas, con un perfil propio. Firefox no tiene ventana de aplicación, así que cada aplicación web conserva sus propios inicios de sesión y no ve los del navegador. |
| Cualquier otro | En un navegador de las dos filas anteriores: uno basado en Chromium si ha instalado alguno, y si no, Firefox. |

El perfil de una aplicación web de Firefox está en `~/.local/share/amethystora-webapp`, o en la
carpeta del navegador dentro de `~/.var/app` cuando el navegador es un Flatpak. Al quitar la
aplicación web, el perfil se elimina, inicios de sesión incluidos.
