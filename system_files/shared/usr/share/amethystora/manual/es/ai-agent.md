# El agente de IA

`Super+Ctrl+Shift+A` abre un agente de IA en una terminal: Claude Code de forma predeterminada, u
Opencode si lo prefiere. Viene con una habilidad (skill) que le explica este sistema, así que sabe qué
archivos pertenecen a la imagen y cuáles puede cambiar usted, cómo funcionan los temas y los atajos de
teclado, cómo se instala software en un sistema basado en imágenes y qué preguntarle antes de tocar
nada.

Pídale cosas en lenguaje corriente:

- «Haz más pequeños los iconos del dock.»
- «¿Por qué el ventilador de mi portátil está siempre en marcha?»
- «Prepara un proyecto de Python con uv en ~/code/scraper.»
- «Añade un atajo de teclado que abra Mission Center.»
- «Crea un widget para la barra superior que muestre el tiempo.» Vea [Widgets](widgets.md).

Arranca en su modo normal, así que pregunta antes de ejecutar un comando o cambiar un archivo. Lea lo
que propone antes de decir que sí.

## Diagnosticar un problema

**Diagnose a problem**, en el menú de Amethystora (`Super+Alt+Space`), le pasa al agente algo que ha
ido mal: un fallo, un servicio que no arrancó o su propia descripción («la wifi se corta tras la
suspensión»). Investiga a partir de los registros y los informes de fallos, no cambia nada y vuelve
con la causa y una propuesta de solución.

```bash
amethystora-agent diagnose                       # look for anything that failed recently
amethystora-agent diagnose "wifi drops after suspend"
amethystora-agent diagnose NetworkManager.service
amethystora-agent diagnose 4242                  # a process ID
```

Las aplicaciones le pasan lo que ha ido mal allí donde usted lo ve: **Preguntar al agente por qué** en
**Actualizaciones** cuando una actualización no terminó, **Preguntar al agente** en **Seguridad** junto
a todo lo que requiere su atención, y **Preguntar al agente** en **Registros** junto a un fallo o algo
que escribió un servicio. Solo transmiten el servicio, el número de proceso o las palabras del propio
informe, y el agente lee el resto por su cuenta. Mientras las funciones del agente están desactivadas,
los botones no aparecen.

## Comandos

| Comando | Qué hace |
| --- | --- |
| `amethystora-agent` | Abre el agente (lo mismo que `Super+Ctrl+Shift+A`) |
| `amethystora-agent ask "<question>"` | Lo abre con una primera pregunta |
| `amethystora-agent diagnose [...]` | Averigua por qué algo se ha estropeado, sin cambiar nada |
| `amethystora-agent use claude` o `use opencode` | Elige el agente |
| `amethystora-agent install` | Instala de antemano el agente elegido; también `ame agent install` |
| `ame agent toggle` | Desactiva las funciones del agente, o las vuelve a activar |

## Instalación y actualización

Los agentes no forman parte de la imagen, porque publican versiones mucho más a menudo que ella. La
primera vez que abre uno, se ofrece a instalarlo en su carpeta personal con el instalador de su propio
fabricante. A partir de entonces se actualiza cuando usted decida: `claude update` u
`opencode upgrade`. Claude Code se instala en su canal estable, con una versión de alrededor de una
semana. Como vive en su carpeta personal, la misma copia funciona también dentro de cualquier toolbox
o distrobox.

## Privacidad y desactivación

Ninguno de los dos agentes hace nada hasta que inicia sesión en él, y lo que le envía va al proveedor
con el que inició sesión. `ame agent toggle` quita las entradas del menú, desactiva el atajo de
teclado y desvincula la habilidad; un agente que haya instalado sigue instalado en cualquier caso.
