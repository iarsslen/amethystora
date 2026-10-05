# Notas y tareas

**Notas**, en la cuadrícula de aplicaciones, reúne sus notas y sus listas de tareas en una sola ventana.
Todo se queda en este equipo. No se sincroniza nada y la aplicación nunca se conecta a Internet.
Sustituye a Joplin y Planify, y trae lo que ya tenga en ellas (vea
[Si viene de Joplin o Planify](#coming-from-joplin-or-planify)).

La primera vez que la abra, le ofrecerá cifrar sus notas con una frase de contraseña. Es la opción
que recomienda, y el resto de esta página da por hecho que la eligió.

## Notas

Las notas se escriben en Markdown y se guardan en libretas, que pueden contener otras libretas. El
editor muestra el texto y la nota con formato uno al lado del otro. **Ctrl+E** alterna entre el texto,
ambos y la nota con formato sola.

- **Listas de comprobación:** `- [ ] like this`. Marque las casillas en la nota con formato.
- **Adjuntos:** pegue una imagen, suelte un archivo sobre la nota o use el clip. Las imágenes se ven en
  la nota. Pulse en cualquier otro adjunto para guardar una copia.
- **Etiquetas:** escriba en la fila de etiquetas, bajo el título, y pulse **Enter**. Las etiquetas
  aparecen en la barra lateral.
- **Mover una nota:** elija otra libreta en la parte superior de la nota, o arrastre la nota a una
  libreta de la barra lateral.
- **Versiones anteriores:** el reloj de la parte superior de una nota. Se guarda una versión cada vez
  que vuelve a cambiar una nota tras diez minutos sin tocarla, hasta las últimas 30. Al restaurar una,
  el texto al que sustituye también se guarda como versión.
- **Papelera:** una nota que elimina va a la papelera, donde puede restaurarla o eliminarla
  definitivamente.
- **PDF:** el menú **⋯** de una nota la exporta como PDF.

## Tareas

**Tareas**, en la parte superior de la barra lateral, cambia a sus listas de tareas:

| Vista | Muestra |
| --- | --- |
| Bandeja de entrada | Las tareas que no están en ningún proyecto |
| Hoy | Lo que vence hoy, y todo lo vencido |
| Próximas | La semana que viene, día a día, y todo lo posterior |
| Fijadas | Las tareas que ha fijado |
| Completadas | Lo que ha terminado, lo más reciente primero |

Los proyectos agrupan tareas y pueden dividirse en secciones. Las etiquetas atraviesan los proyectos.
Pulse en una tarea para establecer su fecha y hora, su repetición, su recordatorio, su prioridad, sus
etiquetas y sus notas, y para añadirle subtareas.

El campo **Añadir una tarea** entiende un poco de lenguaje natural, en inglés. Saca esto del título:

| Escriba | Para |
| --- | --- |
| `today`, `tomorrow`, `friday`, `next week`, `2026-10-31` | La fecha |
| `5pm`, `17:30` | La hora, con un recordatorio a esa hora |
| `every day`, `every 2 weeks`, `monthly` | Una tarea que se repite |
| De `p1` a `p4` | La prioridad; `p1` es la más alta |
| `@errand` | Una etiqueta, que se crea si es nueva |
| `#Garden` | Un proyecto que ya existe |

Al completar una tarea que se repite, pasa a su siguiente fecha.

### Recordatorios

Una tarea con hora puede avisarle, desde **En el momento** hasta **1 día antes**. Los recordatorios
aparecen como notificaciones mientras Notas está en marcha. Al cerrar la ventana, Notas sigue en marcha
en segundo plano hasta que hayan saltado los recordatorios pendientes. Puede desactivarlo en
**Configuración**. Mientras funciona así, sus notas están bloqueadas; solo se guardan, en memoria, los
títulos y las horas de los recordatorios.

## Cifrado

Con el cifrado activado, sus notas, tareas y adjuntos se escriben en el disco cifrados con
AES-256-GCM, con una clave aleatoria que solo puede abrir su frase de contraseña, o una
[llave de acceso](#passkeys) que añada. La frase de contraseña se refuerza con scrypt, que cuesta
128 MiB de memoria por cada intento, así que probar frases una tras otra es lento.

Sigue siendo seguro frente a las computadoras cuánticas. Lo que rompe una computadora cuántica es la
criptografía de clave pública (RSA, curvas elípticas), y aquí no se usa ninguna. Contra un cifrado como
AES, lo más que puede hacer una computadora cuántica es reducir a la mitad la longitud de la clave. Eso
deja a AES-256 con una fortaleza de 128 bits, y por eso AES-256 es lo que el NIST y la CNSA 2.0 de la
NSA mantienen para los años posteriores a las computadoras cuánticas.

> **Nadie puede recuperar una frase de contraseña olvidada.** Ni Amethystora, ni un administrador,
> ni nadie. Guárdela en un lugar seguro, y conserve una [copia de seguridad](#backing-up).

Sus notas se bloquean:

- tras 10 minutos sin usar Notas (**Configuración**, **Bloquear en su ausencia**),
- cuando se bloquea la pantalla, se suspende el equipo o se cierra la ventana,
- cuando pulsa **Ctrl+L** o **Bloquear** en la barra lateral.

**Configuración** también cambia la frase de contraseña, y desactiva o vuelve a activar el cifrado.

### Llaves de acceso

Una llave de seguridad FIDO2 (YubiKey, Thetis o un modelo con huella dactilar como la YubiKey Bio)
puede abrir sus notas, para que no tenga que escribir la frase de contraseña cada vez. La frase de
contraseña sigue funcionando, y es lo que abre sus notas si pierde la llave: una llave de acceso es
una segunda forma de entrar, nunca la única.

Para añadir una, conecte la llave, abra **Configuración** y elija **Añadir una llave de acceso**.
Introduzca su frase de contraseña y el PIN de la llave, o deje el PIN vacío si la llave lee su huella
dactilar. La llave parpadea dos veces; tóquela cada vez. A partir de entonces, la pantalla de bloqueo
ofrece **Abrir con una llave de acceso**, que pide el PIN de la llave, o su huella dactilar, y un
toque.

- **La llave necesita un PIN**, y un modelo con huella dactilar, un dedo registrado. Configúrelos en
  Firefox, en `about:webauthn`. Un toque por sí solo nunca abre sus notas: quien encuentre la llave no
  puede usarla sin el PIN o su dedo, y la llave bloquea su PIN tras ocho intentos fallidos.
- **Añada una segunda llave de reserva**, de una en una. Cada una aparece en **Configuración**, donde
  **Quitar** hace que deje de abrir sus notas.
- **Si pierde una llave**, quítela. Alguien que tenga la llave, conozca su PIN y tenga una copia
  antigua de su carpeta de notas aún podría abrir esa copia. Desactivar el cifrado y volver a activarlo
  da a sus notas una clave nueva, que ninguna llave de acceso quitada abre; después, vuelva a añadir
  las llaves que aún tenga.
- Una [copia de seguridad](#backing-up) siempre pide la frase de contraseña: las llaves de acceso no
  forman parte de ella.

La llave no guarda nada de sus notas. Contiene un secreto que nunca sale de ella y, una vez comprobado
el PIN o la huella, calcula un valor (HMAC-SHA256, el `hmac-secret` de FIDO2) con el que se cifra una
segunda copia de la clave de sus notas. Lo que hay en el disco sigue cifrado solo con AES-256.

## Copias de seguridad

Como no se sincroniza nada, guarde una copia en otro lugar. En **Configuración**:

- **Copia de seguridad en un archivo** escribe un único archivo `.amnotes` con todo dentro, adjuntos
  incluidos, cifrado como sus notas. Se abre con la frase de contraseña que tenía al hacerla, en
  cualquier equipo: elíjalo en **Importar**.
- **Exportar como Markdown** escribe cada nota como un archivo Markdown en una carpeta por libreta, y
  cada proyecto como una lista de comprobación. Estos archivos **no** están cifrados.

Sus notas en sí están en `~/.local/share/amethystora-notes`.

## Si viene de Joplin o Planify

Abra **Configuración** y use **Importar**. Importar de nuevo el mismo archivo actualiza lo que vino de
él en lugar de añadirlo dos veces.

- **Joplin:** en Joplin, elija **Archivo**, **Exportar todo**, **JEX**. Importe el archivo `.jex`.
  Se traen las libretas, las notas, las etiquetas y los adjuntos. Las tareas pendientes de Joplin se
  convierten en tareas de la bandeja de entrada.
- **Planify:** en Planify, abra **Preferencias**, **Copia de seguridad**, y cree una copia. Importe su
  archivo `.json` desde `~/.var/app/io.github.alainm23.planify/data/io.github.alainm23.planify/backups`.
  Se traen los proyectos, las secciones, las tareas, las subtareas, las etiquetas, las fechas y las
  repeticiones.
- Los **archivos Markdown** van a una libreta llamada **Imported**.

Cuando lo tenga todo, puede quitar las aplicaciones antiguas en Bazaar, o con
`flatpak uninstall net.cozic.joplin_desktop io.github.alainm23.planify`.

## Teclas

| Tecla | Qué hace |
| --- | --- |
| **Ctrl+N** | Una nota nueva, o una tarea nueva en **Tareas** |
| **Ctrl+F** | Buscar notas o tareas |
| **Ctrl+1** / **Ctrl+2** | Notas / Tareas |
| **Ctrl+E** | Texto, ambos o la nota con formato |
| **Ctrl+B**, **Ctrl+I**, **Ctrl+K** | Negrita, cursiva, enlace |
| **Ctrl+L** | Bloquear |
| **Ctrl+,** | Configuración |
