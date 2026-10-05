# Moverse por el escritorio

El escritorio es GNOME, organizado para el teclado. Todo lo que se describe aquí funciona también con
el ratón, pero cuando sus dedos se sepan las teclas, rara vez lo necesitará.

## La barra superior

- **A la izquierda**, las seis áreas de trabajo. La que está usando aparece resaltada; pulse otra para
  ir a ella.
- **En el centro**, el reloj. Púlselo, o pulse `Super+V`, para ver las notificaciones y el calendario.
- **A la derecha**, los indicadores de CPU, memoria y red, y después el menú del sistema: wifi,
  sonido, energía y el resto de la configuración rápida.

Los indicadores y las áreas de trabajo siguen los colores del [tema](themes.md) actual. La barra
también puede mostrar [widgets](widgets.md) propios, que el agente de IA crea por usted.

## Encontrar cosas

- `Super+Space` busca aplicaciones, archivos y ajustes, y abre lo que elija.
- `Super` solo abre la vista de actividades: todas las ventanas abiertas a la vez, con la búsqueda
  arriba.
- `Super+A` muestra todas las aplicaciones instaladas.

Las dos búsquedas perdonan las erratas en los nombres de las aplicaciones: `calxu` encuentra
igualmente la Calculadora.

## El portapapeles

`Super+Shift+V` abre el historial del portapapeles: las últimas 15 cosas que copió. Elija una para
volver a copiarla, escriba para buscar y fije las que usa una y otra vez. También es el icono del
portapapeles de la barra superior.

El historial dura lo que dura su sesión, y solo se guardan los elementos fijados. Antes de copiar algo
secreto, active el **Modo privado** en el mismo menú, y no se registrará nada hasta que lo desactive.

## El dock

El dock de la parte inferior contiene sus aplicaciones ancladas y las que están en ejecución. De
`Alt+1` a `Alt+9` cambian a la aplicación de esa posición, y la abren si no está en ejecución. Pulse
con el botón derecho en una aplicación para anclarla o desanclarla.

## El menú de Amethystora

`Super+Alt+Space` abre un único menú con lo que, si no, estaría repartido entre Configuración, la
terminal y [`ame`](terminal.md#ame). Sus entradas están en inglés:

| Entrada | Qué hace |
| --- | --- |
| Ask an agent | Abre el [agente de IA](ai-agent.md) |
| Diagnose a problem | Pide al agente que averigüe por qué algo se ha estropeado |
| Make a widget | Pide al agente que cree un [widget](widgets.md) para la barra superior |
| Theme | El selector de temas |
| Background | Los fondos de pantalla del tema actual |
| Keybindings | Los atajos de teclado, en la terminal |
| Manual | Este manual |
| Web apps | Instalar o quitar una [aplicación web](web-apps.md) |
| Apps and system commands | Todos los comandos de `ame`, cada uno en su grupo |
| System | Bloquear, cerrar la sesión, reiniciar, apagar, buscar actualizaciones, el informe de seguridad |

Muévase con las flechas o escriba para filtrar; `Enter` para elegir, `Esc` para volver.

## Ventanas en mosaico

PaperWM coloca las ventanas por usted. Cada área de trabajo es una tira de ventanas, una al lado de
otra y a toda altura, y la tira puede ser más ancha que la pantalla. Una ventana nueva se abre a la
derecha de la que está usando, las ventanas nunca se superponen, y la tira se desplaza para que la
ventana con el foco quede a la vista:

```
  ┌────────┬──────────────┬──────────────────────┬────────┐
  │  Mail  │   Terminal   │       Browser        │  Chat  │
  └────────┴──────────────┴──────────────────────┴────────┘
           ╰──────────── the screen ─────────────╯
```

Mail y Chat siguen abiertas, justo fuera del borde. `Super+Left` vuelve a Mail. Lleve el puntero
contra el borde izquierdo o derecho de la pantalla para ver lo que hay más allá, y pulse en una
ventana de allí para ir a ella. En un panel táctil, deslice tres dedos para mover la tira.

Las teclas siguen un mismo patrón. `Super` y una flecha llevan a otra ventana. Añada `Ctrl` y lo que
se mueve es la ventana. Añada `Shift` y pasa a otro monitor.

### Moverse

| Tecla | Qué hace |
| --- | --- |
| `Super+Left` / `Super+Right` | La ventana de la izquierda / derecha |
| `Super+Up` / `Super+Down` | La ventana de arriba / abajo, cuando varias ventanas comparten columna |
| `Super+Home` / `Super+End` | La primera / última ventana del área de trabajo |
| `Super+[` / `Super+]` | Desplazar la tira sin cambiar la ventana con el foco |
| `Super+Shift` y una flecha | El monitor en esa dirección |

### Organizar

| Tecla | Qué hace |
| --- | --- |
| `Super+Ctrl+Left` / `Super+Ctrl+Right` | Mover la ventana a la izquierda / derecha en la tira |
| `Super+Ctrl+Up` / `Super+Ctrl+Down` | Moverla arriba / abajo en su columna |
| `Super+I` | Traer la ventana de la derecha a esta columna, debajo de esta |
| `Super+O` | Sacar la ventana de abajo de esta columna a una columna propia |
| `Super+Shift+O` | Sacar esta ventana a una columna propia |
| `Super+Ctrl+Page Up` / `Page Down` | Moverla al área de trabajo anterior / siguiente |
| `Super+Shift+Ctrl` y una flecha | Moverla al monitor en esa dirección |
| `Super+T`, manteniendo `Super` pulsada | Llevar la ventana consigo mientras se mueve, y dejarla donde suelte la tecla |

### Tamaño

| Tecla | Qué hace |
| --- | --- |
| `Super+R` | Cambiar el ancho entre el 38 %, el 50 % y el 62 % de la pantalla (`Super+Alt+R` retrocede) |
| `Super+Shift+R` | Lo mismo para la altura de una ventana en una columna |
| `Super+F` | Ocupar todo el ancho de la pantalla, y volver |
| `Super+C` | Centrar la ventana en la pantalla |
| `Super+Shift+C` | Hasta dónde desplaza la tira una ventana con el foco: justo a la vista, al centro o al borde |
| `Super+Shift+W` | Dónde se abren las ventanas nuevas: a la derecha, a la izquierda o debajo de esta |

### Ventanas flotantes

Los diálogos flotan solos sobre la tira. `Super+Ctrl+Escape` saca de la tira la ventana con el foco
para que también flote, y la vuelve a poner en ella. `Super+Alt+Escape` oculta a la vez todas las
ventanas que flotan de esa forma, y las vuelve a mostrar.

### Y lo demás

| Tecla | Qué hace |
| --- | --- |
| `Super+N` | Una ventana nueva de la aplicación que está usando |
| `Super+Ctrl+B` | Ocultar o mostrar la barra superior en esta área de trabajo |

La configuración de PaperWM está en **PaperWM**, dentro del **Gestor de extensiones**. Incluye los
espacios entre ventanas, los anchos que recorre `Super+R` y todas las teclas, algunas de las cuales
esta página no menciona.

### Ventanas clásicas

Si prefiere ventanas que floten y se superpongan, como en Windows y macOS, cambie a la disposición
clásica:

```bash
ame desktop layout classic
```

Desactiva PaperWM, y las actualizaciones lo dejan desactivado. Las ventanas se abren entonces donde
GNOME las coloca y se arrastran por la barra de título. `Super+Up` maximiza y `Super+Down` restaura,
`Super+Left` / `Super+Right` colocan una ventana en esa mitad de la pantalla, y `Super+Shift+Left` /
`Super+Shift+Right` la mueven al monitor siguiente. `ame desktop layout tiling` recupera la tira. La
primera vez que inicia sesión, una notificación le ofrece la misma elección.

## Ventanas

| Tecla | Qué hace |
| --- | --- |
| `Super+W` | Cerrar la ventana |
| `Super+Backspace` | Cambiar el tamaño con las flechas |
| `Shift+F11` | Pantalla completa, conservando la barra de título |
| `Super+Tab` / `Alt+Tab` | Cambiar de aplicación / de ventana |

Los botones de la derecha de cada barra de título minimizan, maximizan y cierran.

## Áreas de trabajo

Siempre hay seis, así que `Super+3` siempre lleva al mismo sitio. Una forma habitual de usarlas: un
navegador en la 1, una terminal en la 2 y el chat en la 6. `Super+Shift+3` lleva la ventana con el
foco al área de trabajo 3. `Super+Page Up` / `Super+Page Down` van al área de trabajo anterior /
siguiente, y `Super+Shift+Ctrl+Left` / `Super+Shift+Ctrl+Right` mueven la ventana al monitor
siguiente.

## Extensiones

Estas extensiones de GNOME Shell vienen con la imagen:

| Extensión | Qué hace |
| --- | --- |
| PaperWM | [Mosaico](#tiling-windows): ventanas una al lado de otra en una tira que se desplaza |
| Space Bar | Las áreas de trabajo en la barra superior |
| TopHat | Los indicadores de CPU, memoria y red |
| Dash to Dock | El dock |
| Search Light | La búsqueda de `Super+Space` |
| Fuzzy App Search | Una búsqueda de aplicaciones que perdona las erratas |
| Clipboard Indicator | El [historial del portapapeles](#the-clipboard) de `Super+Shift+V` |
| Blur my Shell | El cristal esmerilado detrás del panel, la vista de actividades y las ventanas |
| Just Perfection | Animaciones más rápidas, y ningún aviso emergente al cambiar de área de trabajo |
| AppIndicator | Iconos de bandeja para las aplicaciones que los usan |
| Caffeine | Un interruptor en la configuración rápida que mantiene la pantalla encendida |
| GSConnect | Su teléfono Android: notificaciones, archivos, portapapeles, mensajes |
| Logo Menu | El logotipo de Amethystora arriba a la izquierda: accesos directos a herramientas del sistema |
| Gradia | Anotar una captura de pantalla justo después de hacerla |
| Bazaar integration | Conecta la shell con Bazaar, el centro de software |

Puede desactivar cualquiera de ellas, o cambiar su configuración, en el **Gestor de extensiones**.
Algo que conviene saber: después de cada actualización de la imagen, las extensiones propias de la
imagen se vuelven a activar, para que una que se haya desactivado por accidente, o por un fallo, no
se quede desactivada para siempre. Desactivar una dura hasta la próxima actualización. La excepción es
PaperWM con la [disposición clásica](#classic-windows), que sigue desactivado.

## Archivos

`Super+Shift+F` abre una ventana de Archivos y `Super+E` su carpeta personal. Las carpetas se abren en
cuadrícula, donde las carpetas del tema de iconos se ven como las ilustraciones que son.
