# Temas

Un tema es una paleta, y todo se pinta a partir de ella. Al cambiar de tema, todo el escritorio cambia
a la vez: el estilo claro u oscuro y el color de acento de GNOME, la terminal, el prompt de la shell,
la barra superior, el dock, el fondo de pantalla, VSCodium y este manual. Un tema claro da al dock un
ligero tinte oscuro, para que sus iconos sigan destacando sobre un fondo pálido.

## Cambiar de tema

| Tecla | Qué hace |
| --- | --- |
| `Super+Ctrl+Shift+Space` | Elegir un tema |
| `Super+Ctrl+D` | Alternar entre la versión clara y la oscura del tema |
| `Super+Ctrl+Space` | Siguiente fondo de pantalla del tema actual |

Lo mismo desde una terminal:

```bash
ame desktop theme                   # pick one from a list
amethystora-theme list              # the themes, with the current one marked
amethystora-theme set "Tokyo Night" # apply one by name
amethystora-theme toggle            # light or dark
amethystora-theme current           # which one is on
```

## Los temas

| Tema | Nombre que usar | Estilo |
| --- | --- | --- |
| Amethystora | `amethystora` | Oscuro, el predeterminado |
| Amethystora Light | `amethystora-light` | Claro |
| Catppuccin Mocha | `catppuccin` | Oscuro |
| Catppuccin Latte | `catppuccin-latte` | Claro |
| Everforest | `everforest` | Oscuro |
| Gruvbox | `gruvbox` | Oscuro |
| Matte Black | `matte-black` | Oscuro |
| Nord | `nord` | Oscuro |
| Rosé Pine Dawn | `rose-pine-dawn` | Claro |
| Tokyo Night | `tokyo-night` | Oscuro |

Los dos temas Amethystora traen además el tema GTK de Amethystora, el de las tres luces de colores en
la esquina de cada ventana. Los demás conservan el aspecto propio de GNOME con su color de acento.
`Super+Ctrl+D` cambia un tema por su pareja (Catppuccin Mocha y Latte, Amethystora y Amethystora
Light); un tema sin pareja cambia a Amethystora en el otro modo.

## Fondos de pantalla

Cada tema trae tres fondos de pantalla de lugares imaginarios dibujados en sus propios colores, y al
cambiar a un tema se pone el primero en el escritorio: una ciudad de neón bajo la lluvia para Tokyo
Night, una aurora sobre un lago de montaña para Nord, pinos entre la niebla para Everforest, una
puesta de sol en el desierto para Gruvbox, cumbres bajo una luna pastel para Catppuccin, un eclipse
para Matte Black, etcétera. `Super+Ctrl+Space` los va alternando. Los dos temas Amethystora empiezan
con las facetas de una piedra tallada, y tienen también el campo de cristales y un cielo nocturno de
humo violeta; la Configuración de GNOME los ofrece en Apariencia.

Para añadir los suyos, ponga imágenes (JPG, PNG, WebP o SVG) en una carpeta con el nombre del tema.
Van detrás de las imágenes propias del tema:

```bash
mkdir -p ~/.config/amethystora/backgrounds/amethystora
cp ~/Pictures/mountains.jpg ~/.config/amethystora/backgrounds/amethystora/
```

`amethystora-theme bg list` muestra lo que puede alternar el tema actual, y
`amethystora-theme bg set <picture>` pone uno directamente.

## Transiciones

Un tema o un fondo nuevo no aparece sin más. La pantalla se queda quieta un momento mientras todo
cambia por debajo, y luego el escritorio nuevo se abre en un círculo desde el puntero, con un
resplandor del color de acento del tema en el borde. Funciona igual se haga el cambio como se haga:
con las teclas de arriba, desde la Configuración de GNOME o con el botón Estilo oscuro de la
configuración rápida.

```bash
ame desktop transition         # pick one from a list
ame desktop transition wave    # or name it
```

| Transición | Aspecto |
| --- | --- |
| `grow` | Un círculo se abre desde el puntero. La predeterminada |
| `outer` | El escritorio nuevo se cierra sobre el puntero desde los bordes |
| `wipe` | Un borde suave barre la pantalla en diagonal |
| `wave` | Lo mismo, con un borde ondulado |
| `fade` | Un fundido simple |
| `random` | Una de las cuatro primeras, con cualquier ángulo |
| `none` | Sin animación: el fondo se funde como lo funde GNOME |

Una transición dura 1,2 segundos. Para cambiarlo, indique la duración en milisegundos:

```bash
gsettings set org.gnome.shell.extensions.amethystora-transitions duration 800
```

No hay transiciones mientras las animaciones estén desactivadas en Configuración, en Accesibilidad.
Vienen de la extensión Amethystora Transitions, que se puede desactivar en el Gestor de extensiones.

## Iconos

Los iconos son candy-icons, el mismo conjunto con todos los temas: sus carpetas, sus tipos de archivo y
sus pictogramas con degradado para las aplicaciones que hacen una tarea sencilla, como Archivos,
Configuración o la calculadora. Una aplicación con un logotipo propio lo conserva. Firefox,
Thunderbird, un IDE de JetBrains y la mayor parte de lo que instale muestran el icono que dibujó su
fabricante, no uno redibujado: un logotipo es una marca registrada, y su aspecto lo decide su
propietario. Por eso el dock mezcla los dos estilos.

## Modificar un tema o crear uno propio

Los temas vienen de solo lectura en `/usr/share/amethystora/themes`. Una carpeta con el mismo nombre en
`~/.config/amethystora/themes` se superpone a ellos, así que solo tiene que escribir los archivos que
quiera cambiar. Una carpeta con un nombre propio es un tema nuevo. Cada archivo es pequeño y opcional,
salvo la paleta:

| Archivo | Contiene |
| --- | --- |
| `colors.toml` | La paleta: `accent`, `foreground`, `background`, `cursor`, `selection_foreground`, `selection_background`, y de `color0` a `color15` |
| `light.mode` | Presente, y vacío, cuando el tema es claro |
| `pair.theme` | El tema al que cambia `Super+Ctrl+D` |
| `accent.theme` | El color de acento de GNOME: blue, teal, green, yellow, orange, red, pink, purple o slate. Sin él, se elige el más parecido |
| `gtk.theme` | Un nombre de tema GTK, en lugar del aspecto propio de GNOME |
| `icons.theme` | Un tema de iconos, en lugar de candy-icons |
| `cursor.theme` | Un tema de cursor |
| `vscode.theme` | El tema de color de VSCodium al que cambiar |
| `tophat.theme` | El color de los indicadores de la barra superior, cuando el acento se ve mal como línea fina |
| `backgrounds/` | Fondos de pantalla |
| `backgrounds.list` | Fondos de pantalla guardados en otro lugar del sistema, una ruta por línea. El primero es con el que empieza el tema |

Un tema sin imágenes propias recibe cuatro dibujadas en sus colores: un resplandor suave, colinas
entre la bruma, un mapa topográfico y cintas ondulantes.

Un tema propio se crea con tres comandos:

```bash
mkdir -p ~/.config/amethystora/themes/sunset
cp /usr/share/amethystora/themes/amethystora/colors.toml ~/.config/amethystora/themes/sunset/
amethystora-theme set sunset
```

Edite los colores, vuelva a ejecutar `amethystora-theme set sunset` y mire el resultado.

## Ir más allá

- **Cómo se escribe una configuración.** La paleta de la terminal, el prompt, los colores de btop y
  los fondos dibujados son plantillas en `/usr/share/amethystora/themed`. Copie una en
  `~/.config/amethystora/themed/` y edite la copia para cambiar cómo la genera cada tema.
- **Ejecutar algo en cada cambio.** Ponga un ejecutable en
  `~/.config/amethystora/hooks/theme-set.d/`. Recibe el nombre del tema en `AMETHYSTORA_THEME` y su
  carpeta en `AMETHYSTORA_THEME_DIR`.
- **Su propio prompt sigue siendo suyo.** Si ha escrito usted mismo `~/.config/starship.toml`, el
  tema no lo toca.
- **No edite nunca `~/.config/amethystora/current/`.** Se reescribe en cada cambio.

## El menú de arranque

El menú de arranque también puede llevar las ilustraciones de Amethystora. Está desactivado de forma
predeterminada, porque el menú de arranque está fuera de la imagen:

```bash
ame desktop boot-menu
```

Vuelva a ejecutarlo para quitar las ilustraciones. Una vez activado, las actualizaciones de la imagen
lo mantienen al día.
