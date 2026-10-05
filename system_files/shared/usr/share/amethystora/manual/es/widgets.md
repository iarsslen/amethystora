# Widgets

La barra superior puede mostrar cosas suyas: un temporizador de concentración, el tiempo, el correo
sin leer, si la VPN está conectada, cuántas pull requests esperan su revisión. Cada una es un
*widget*, un pequeño programa cuya salida la barra convierte en una etiqueta, un icono y un menú. No
tiene que escribirlo usted: lo hace el [agente de IA](ai-agent.md).

## Pedir uno al agente

Elija **Make a widget** en el menú de Amethystora (`Super+Alt+Space`) y diga qué debe mostrar, o
ejecute:

```bash
amethystora-widgets make "a pomodoro timer"
amethystora-widgets make "how many pull requests wait for my review on GitHub"
amethystora-widgets make                          # the agent asks you what you want
```

El agente escribe el widget y lo comprueba, y el widget aparece en la barra en cuanto se guarda, sin
necesidad de cerrar la sesión. Pida cambios de la misma forma: «haz que el widget del tiempo muestre
también mañana».

Cuando un widget deja de funcionar, la barra muestra una señal de advertencia en su lugar. Púlsela
para leer qué ha ido mal; **Fix it with the AI agent** le pasa el problema al agente.

## Comandos

| Comando | Qué hace |
| --- | --- |
| `amethystora-widgets` | Lista sus widgets, y cuáles están activados |
| `amethystora-widgets make ["<idea>"]` | Pide al agente que cree uno |
| `amethystora-widgets new <name> [<example>]` | Empieza uno a partir de un ejemplo: `hello`, `pomodoro` o `do-not-disturb` |
| `amethystora-widgets run <name>` | Lo ejecuta una vez como lo hace la barra, y dice qué le pasa |
| `amethystora-widgets fix <name> ["<what is wrong>"]` | Pide al agente que averigüe por qué falla y lo arregle |
| `amethystora-widgets off <name>` y `on <name>` | Lo oculta de la barra, o lo vuelve a mostrar |
| `amethystora-widgets remove <name>` | Lo mueve a la papelera |
| `amethystora-widgets restart` | Detiene e inicia todos los widgets |

`ame desktop widgets` ejecuta los mismos comandos.

## Crear uno usted mismo

Un widget es una carpeta en `~/.config/amethystora/widgets` que contiene un `widget.json`, que indica
un comando y cada cuánto ejecutarlo, y el propio comando, normalmente un script corto. El script
imprime una línea para que la barra la muestre: texto sin formato, o JSON con un icono, un color del
tema y un menú cuyos elementos ejecutan comandos, abren enlaces o accionan interruptores.

`amethystora-widgets new mywidget` copia el ejemplo `hello` en su sitio como punto de partida, y
`amethystora-widgets run mywidget` lo comprueba tras cada cambio. El formato completo está en la guía
del propio agente, `/usr/share/amethystora/agents/skills/amethystora-widgets/SKILL.md`; los ejemplos
están en `/usr/share/amethystora/widgets/examples`.

## Seguridad

Un widget se ejecuta como usted, con acceso a sus archivos, como cualquier programa que inicie.
Conserve solo los widgets que haya leído o que haya pedido al agente, y lea lo que propone el agente
antes de decir que sí, ya que pregunta antes de escribir nada.

Los widgets se ejecutan fuera de GNOME Shell, así que uno roto o lento muestra una señal de
advertencia en lugar de congelar el escritorio o cerrar su sesión. Se detienen mientras la pantalla
está bloqueada.
