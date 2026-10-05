# Seguridad

Amethystora está reforzado más allá de los valores predeterminados de Fedora, y lo dice claramente:
todo lo que sigue se puede comprobar, y casi todo se puede cambiar si le estorba.

## Ver en qué punto está

Abra **Seguridad** desde la cuadrícula de aplicaciones, o ejecute:

```bash
ame security status
```

Ambos muestran lo que hacen realmente ahora mismo los ajustes de seguridad, con qué hacer con lo que
esté desactivado, y ninguno cambia nada ni pide contraseña. En la aplicación, lo que requiere su
atención aparece primero, con el comando que lo corrige y un botón que lo ejecuta en una terminal, y
las protecciones descritas más abajo, desactivadas hasta que las quiera, están cada una a un botón de
distancia. Para un examen más a fondo, `ame security audit` hace pasar Lynis por unos cientos de
comprobaciones y explica cada hallazgo.

La página **Aplicaciones** de la aplicación lista a qué puede acceder cada aplicación Flatpak fuera de
su entorno aislado, y qué parte de ello se concedió en este equipo
([Permisos de las aplicaciones](#app-permissions)).

La página **Contenedores** de la aplicación lista lo que está instalado fuera de Flatpak: los
contenedores que creó `amepkg`, las aplicaciones de su cuadrícula de aplicaciones que vienen de ellos y
lo que se compiló desde el AUR, cada uno con la fecha de su última actualización. El informe le avisa
cuando uno lleva dos semanas sin actualizarse. [Contenedores](software.md#containers).

Cuando algo requiere su atención, **Preguntar al agente** se lo pasa al [agente de IA](ai-agent.md),
que lo investiga en una terminal y no cambia nada hasta que usted esté de acuerdo.

## Activado desde el principio

- **Las actualizaciones deben estar firmadas.** Solo se instalan imágenes firmadas con la clave de
  Amethystora, así que una imagen manipulada o sustituida se rechaza.
  [Actualizaciones](updates.md#signed-updates).
- **El cortafuegos rechaza las conexiones entrantes.** Se permiten el descubrimiento de impresoras y
  dispositivos, el uso compartido de archivos de Windows, la configuración de IPv6 y GSConnect; su
  tailnet de Tailscale es de confianza. Para dejar entrar algo más, como un servidor de desarrollo al
  que quiera llegar desde su teléfono, use la aplicación **Cortafuegos** o
  `sudo firewall-cmd --add-port=8080/tcp` (añada `--permanent` para conservarlo tras un reinicio).
- **Diez contraseñas incorrectas seguidas** bloquean una cuenta durante diez minutos. Desbloquéela
  antes desde otra cuenta de administrador con `sudo faillock --user <name> --reset`.
- **Los inicios de sesión fallidos repetidos por la red** hacen que se bloquee la dirección: cinco
  fallos en diez minutos cuestan una hora, y cada nuevo bloqueo de la misma dirección dura más, hasta
  un día. Vigila el servidor SSH, lo único de aquí en lo que se puede iniciar sesión por la red, y deja
  en paz a la tailnet. `ame security addresses` lista lo que está bloqueado, y
  `ame security addresses <address>` vuelve a dejar entrar una dirección.
- **El servidor SSH está desactivado,** y rechaza los inicios de sesión de root cuando lo activa.
- **Las aplicaciones no pueden espiar el teclado de las demás.** A las aplicaciones Flatpak se les
  niegan X11 y los dispositivos de entrada
  ([Instalar software](software.md#what-flatpak-apps-may-not-do)), y el reasignador de teclas, que lee
  cada tecla, está desactivado hasta que lo pida.
- **El núcleo está reforzado:** la memoria se borra al asignarse, las direcciones del núcleo están
  ocultas, los programas no pueden leer la memoria de otros, y los módulos poco usados (protocolos de
  red y sistemas de archivos antiguos, FireWire) no pueden cargarse. `gdb -p` sobre un proceso que no
  inició usted necesita `sudo`.
- **El núcleo no se deja reescribir mientras se ejecuta.** El bloqueo (lockdown) impide cargar módulos
  que no son de confianza, escribir en `/dev/mem` y trazar la memoria del núcleo con BPF, así que un
  compromiso de root termina en el siguiente reinicio. Necesita Secure Boot activado y la clave
  registrada ([Hardware](hardware.md#secure-boot)). En un equipo en el que no se puede activar Secure
  Boot, quítelo con `sudo rpm-ostree kargs --delete=lockdown=integrity`. Las imágenes NVIDIA no lo
  usan.
- **Se vigila lo que sobreviviría a un reinicio, y se le avisa.** El registro de auditoría anota los
  cambios en las cuentas, en quién puede usar `sudo`, en lo que se inicia solo (sus entradas de inicio
  automático, sus propios servicios de systemd, los archivos de inicio de la shell) y en los ajustes de
  seguridad, y cada programa que abre un dispositivo de entrada. El vigilante de seguridad lo lee cada
  15 minutos e indica qué cambió y qué programa lo cambió.
  [El vigilante de seguridad](#the-security-watcher).
- **Cada semana se ejecuta un análisis de virus** en sus carpetas personales y temporales, y **Lynis
  audita la configuración cada mes.** De forma predeterminada, ninguno de los dos elimina ni mueve
  nada: un falso positivo que le quita un archivo que quería es peor que casi todo lo que eliminaría.
  `ame security scan` muestra lo que encontró el último análisis, y `ame security scan now` ejecuta
  uno. [Analizar en busca de virus](#scanning-for-viruses) hace lo mismo en una ventana, y
  [Ajustes](#settings) hace que los análisis pongan en cuarentena o eliminen lo que encuentren.

## El vigilante de seguridad

Cada 15 minutos, o en el momento en que ocurren las cosas si la
[vigilancia en tiempo real](#settings) está activada, el vigilante examina:

- **El registro de auditoría**: las cuentas, las reglas de `sudo`, lo que se inicia solo, los ajustes
  de seguridad y los módulos del núcleo cargados desde una sesión, cada uno con el programa que hizo el
  cambio. Un programa que abre el teclado directamente se notifica la primera vez que ese programa lo
  hace; los juegos y los reasignadores de teclas también lo hacen.
- **El diario**: una cuenta bloqueada tras contraseñas incorrectas, tres o más contraseñas incorrectas
  de `sudo` o de administrador, y los dispositivos USB que bloqueó la
  [protección USB](#block-usb-devices-you-did-not-plug-in).
- **`/etc` frente a la imagen**: la imagen guarda su propia copia de `/etc` en `/usr/etc`, así que un
  ajuste de seguridad cambiado, o un archivo de `/etc` que sustituye a uno de la imagen en `/usr/lib`,
  aparece como **Ajustes de la imagen** en el informe.
- **Lo que no debería existir en este sistema**: un programa setuid fuera de `/usr`,
  `/etc/ld.so.preload`, un archivo normal en `/dev`, un módulo del núcleo que no vino con la imagen o
  no está firmado, y una interfaz de red que lee todos los paquetes. Son las
  **Comprobaciones de rootkits** del informe.
- **Lo que acepta conexiones**: cada programa que escucha en la red, al que puede llegar cualquier
  dispositivo de su tailnet. Uno nuevo se notifica una vez.
- **Lo que su sesión encuentra primero**: un programa en `~/.local/bin`, `~/bin` o la carpeta de
  Homebrew que se llame como uno de los comandos del sistema, y que su shell ejecuta en lugar del real.
  Un `sudo` o un `ssh` falso ahí es una forma antigua de robar una contraseña, así que esos se notifican
  con más fuerza; la carpeta de Homebrew solo cuenta para esos. Y un lanzador de su cuadrícula de
  aplicaciones que no creó ninguna exportación de contenedor. Cada uno se notifica cuando aparece, y de
  nuevo si cambia.
- La **protección de red**, mientras está activada: cada conexión que bloqueó, con la forma de volver
  a permitirla, y lo que reconoció sin bloquear cuando la regla lo califica de grave.
  [Protección de red](#network-protection).
- **El propio informe**: cuando una comprobación que indica que algo se desactivó, como el
  cortafuegos, las actualizaciones firmadas o el registro de auditoría, deja de estar bien.

Todo lo nuevo llega como notificación, y espera en el informe hasta que lo lea:

```bash
ame security events
```

`ame security events now` mira antes. Si hizo usted el cambio, o instaló algo que lo hizo, no hay nada
que hacer.

## Permisos de las aplicaciones

Cada aplicación Flatpak se ejecuta en un entorno aislado, y sus permisos indican hasta dónde puede
llegar fuera de él sin preguntarle. La página **Aplicaciones** de la aplicación Seguridad, y
`ame security apps` en una terminal, listan para cada aplicación a qué puede acceder, e indican qué
parte de ello se concedió en este equipo en lugar de pedirlo la propia aplicación:

| Qué puede hacer | Qué significa |
| --- | --- |
| Comunicarse con todos los servicios de su sesión o del sistema, usar el servicio de Flatpak o el systemd de su sesión, o poner un programa donde se inicie en su próximo inicio de sesión | Puede salir de su entorno aislado: lo que se ejecute en ella puede hacer todo lo que usted puede hacer |
| Usar X11, o leer los dispositivos de entrada | Puede ver lo que escribe en otras aplicaciones. La imagen quita ambas cosas a todas las aplicaciones, así que una aplicación solo las tiene si se le volvieron a conceder |
| Usar todos los dispositivos | Cámaras, llaves de seguridad y mandos de juego, sin preguntar |
| Leer y cambiar sus archivos, o solo leerlos | Todo lo que hay en su carpeta personal, o todos los archivos que usted puede abrir |
| Usar sus claves SSH o GPG, o leer su depósito de claves | Iniciar sesión, firmar o descifrar como usted, o leer todas las contraseñas que guardó |

Lo que una aplicación pide mediante un portal, como un archivo que usted elige para ella, se pregunta
cada vez y no aparece en la lista. El informe de seguridad indica cuándo una aplicación puede salir de
su entorno aislado, y cuándo a una se le devolvió X11 o los dispositivos de entrada. Si no era su
intención, cámbielo en **Flatseal**, o retire todo lo que concedió a una aplicación con
**Retirar lo que concedió** en la página Aplicaciones, o:

```bash
ame security apps reset
```

## Compartir archivos sin lo que dicen de usted

Las fotos, los documentos y las grabaciones llevan más de lo que muestran: dónde se tomó una foto y con
qué teléfono, quién escribió un documento y cuándo. **Limpiador de metadatos** (Metadata Cleaner)
muestra lo que un archivo dice de usted y guarda una copia sin ello. Ábralo desde la cuadrícula de
aplicaciones y añada los archivos antes de enviarlos o publicarlos.

## Analizar en busca de virus

**Análisis de virus**, en la aplicación **Seguridad** (o `amethystora-security scan`), analiza cuando
usted lo pida:

- **Su carpeta personal**, salvo las cachés.
- **Un archivo o una carpeta**: elíjalo, o suéltelo en cualquier parte de la ventana.
- **Todo el equipo**: todas las carpetas personales y temporales, como hace el análisis semanal. No
  pide contraseña y continúa si cierra la ventana. Lo que encuentra se guarda donde solo un
  administrador puede leerlo, así que para verlo sí se pide su contraseña.

Un análisis que inicia usted se ejecuta como usted, así que comprueba lo que su cuenta puede leer. De
forma predeterminada, nada de lo que encuentra se elimina, se pone en cuarentena ni se mueve: el
resultado lista cada archivo, con **Mostrar en Archivos**, y le deja a usted la decisión. Una
coincidencia puede ser un falso positivo, así que compruebe de dónde viene un archivo antes de
eliminarlo, y después vuelva a analizar. Si configura los análisis para poner en cuarentena o
eliminar, la aplicación le pide su contraseña cuando termina el análisis e indica qué pasó con cada
archivo. Los análisis que ha hecho figuran en `~/.local/state/amethystora/security-scans.json`.

## Ajustes

```bash
ame security settings
```

- **Qué pasa con lo que encuentra un análisis de virus**: `report` (el valor predeterminado) lo deja
  donde está, `quarantine` lo mueve a `/var/lib/amethystora/quarantine`, donde nada puede abrirlo ni
  ejecutarlo, y `delete` lo elimina. Se aplica al análisis semanal, a los análisis que inicia en la
  aplicación y al análisis en tiempo real. Cada archivo se vuelve a comprobar antes de hacer nada con
  él. `ame security scan quarantine` lista lo que hay en cuarentena, y `ame security scan restore`
  devuelve un archivo a su sitio y puede indicar al analizador que, a partir de entonces, deje en paz
  ese archivo concreto.
- **Vigilancia en tiempo real**: `off` (el valor predeterminado) u `on`. Cuando está activada, el
  vigilante de seguridad lee cada cambio en cuanto lo anota el registro de auditoría, y cada archivo
  escrito en una carpeta personal se analiza al cerrarse. Consume algo de CPU mientras se escriben
  archivos, y el análisis empieza cuando se han descargado las primeras firmas de virus.
- **Protección de red**: `off` (el valor predeterminado), `watch` o `block`.
  [Protección de red](#network-protection).

Los tres se guardan en `/etc/amethystora/security.conf`. El comando aplica un cambio de inmediato; una
modificación manual del archivo se aplica en el siguiente reinicio.

## Merece la pena activarlo

### Llaves de seguridad

Una llave de seguridad FIDO2 (YubiKey, Thetis o un modelo con huella dactilar como la YubiKey Bio)
puede iniciar su sesión, desbloquear la pantalla y aprobar `sudo` y las peticiones de administrador
en lugar de su contraseña:

```bash
ame security key
```

Elija **Add a fingerprint key** para un modelo con huella dactilar, de modo que la llave compruebe su
huella y no solo un toque. Antes, la llave necesita un PIN, y un modelo con huella dactilar, un dedo
registrado: configúrelos en Firefox, en `about:webauthn`, o con `ykman fido fingerprints add` en una
YubiKey Bio.
Registre una segunda llave de reserva. Su contraseña sigue funcionando siempre que no haya conectada
ninguna llave registrada.

### Inicio de sesión con huella dactilar

En un equipo con lector de huellas, un dedo puede iniciar su sesión, desbloquear la pantalla y aprobar
`sudo` y las peticiones de administrador, y su contraseña sigue funcionando a la vez:

```bash
ame security fingerprint
```

**Add a finger** registra uno; registre un segundo de reserva. **Configuración › Sistema › Usuarios**
hace lo mismo en **Inicio de sesión con huella**. Dos cosas siguen pidiendo la contraseña: la frase
de contraseña del disco al arrancar, y el depósito de claves, que un inicio de sesión con el dedo deja
bloqueado hasta que una aplicación lo necesita. Los lectores que funcionan están en
[fprint.freedesktop.org](https://fprint.freedesktop.org/supported-devices.html).

### Control parental

Para la cuenta de un niño, conviértala en una cuenta estándar, no de administrador, en
**Configuración › Sistema › Usuarios**, y después abra **Control parental** desde la cuadrícula de
aplicaciones, o desde la página de esa cuenta en Configuración. Decide qué aplicaciones instaladas
puede abrir la cuenta, si puede instalar aplicaciones y hasta qué clasificación por edades y, desde
GNOME 50, cuánto tiempo al día puede usar el equipo y a partir de qué hora de la noche no puede.
Cuando se acaba el tiempo, la pantalla se bloquea.

### Copias de seguridad

```bash
ame backup
```

Una copia de seguridad diaria con restic en un repositorio del que el ransomware de este equipo no
puede borrar nada. La copia solo añade al repositorio y nunca elimina instantáneas antiguas, así que
un repositorio de solo anexado en el otro extremo conserva todo lo copiado antes de un ataque. El
comando explica cómo configurar uno en rest-server, Borg, un almacenamiento de objetos con
inmutabilidad o una unidad USB que desconecte entre copias. `ame backup now` hace una copia de
inmediato, y `ame backup snapshots` lista lo que hay.

Cada copia guarda también su configuración junto a sus archivos: la imagen y el canal que sigue, sus
aplicaciones Flatpak y de dónde vinieron, sus paquetes de Homebrew, los contenedores que creó `amepkg`
con lo que instaló en ellos, las extensiones de GNOME que tenía activadas y su tema. No incluye
contraseñas, claves ni tokens. En un equipo nuevo, apunte `ame backup` al mismo repositorio con la
misma contraseña, y después:

```bash
ame restore-setup
```

Primero muestra lo que haría, y solo hace las partes que elija: cambiar a la misma imagen, mediante
`ame system rebase`, que solo acepta imágenes firmadas; instalar las aplicaciones y los paquetes de
Homebrew; volver a crear los contenedores e instalar lo que había en ellos; volver a activar las
extensiones; poner el tema. `ame restore-setup <snapshot>` elige una configuración anterior. Sus
archivos en sí se recuperan con restic.

### Protección contra ransomware

```bash
ame security ransomware
```

Cada hora, una instantánea de solo lectura de cada carpeta personal de este equipo, guardada en
`/var/home/.snapshots`. Un ransomware que se ejecute como usted puede cifrar todo lo que usted puede
escribir, y una instantánea no es algo que pueda escribir: cambiar o eliminar una requiere un
administrador. Se conservan todas las instantáneas del último día, y una al día durante dos semanas.
El informe le avisa cuando la más reciente tiene más de unas horas.

Para recuperar archivos, ejecute `ame security ransomware restore` y elija el momento al que volver.
**Open it in Files** muestra su carpeta personal tal como estaba entonces, para copiar de ella;
**Put a folder back** vuelve a copiar una carpeta entera en su sitio, sustituyendo los archivos que
tiene y dejando los que no, como los que renombró el ransomware. En una instantánea no se ven los
archivos de nadie más, y los suyos no son visibles para los demás.

Necesita las carpetas personales en un subvolumen btrfs propio, que es como el instalador prepara un
disco salvo que se particione a mano. El coste es espacio en disco: una instantánea retiene lo que se
ha cambiado o eliminado desde entonces, así que un archivo que elimine para hacer sitio solo libera su
espacio cuando desaparece la última instantánea que lo contiene, hasta dos semanas después. Las
instantáneas nunca se eliminan para hacer sitio, porque entonces un ransomware que reescribiera todos
los archivos eliminaría las de antes de él. Al desactivar la protección, se ofrece eliminarlas.

Las instantáneas están en el mismo disco, y un ransomware que consiga derechos de administrador puede
eliminarlas. Guarde también una [copia de seguridad](#backups) en otro lugar.

### Desbloquear el disco con el TPM

```bash
ame security disk-unlock
```

En lugar de escribir la frase de contraseña del disco en cada arranque, el TPM del equipo entrega la
clave, pero solo mientras Secure Boot esté activado y las claves de firma sean las que estaban
registradas cuando lo configuró. Añada un PIN si quiere que el disco necesite además algo que usted
sabe. Su frase de contraseña sigue funcionando, así que un TPM borrado nunca le deja fuera. Necesita
un disco que se cifró al instalarlo.

### Bloquear los dispositivos USB que no conectó usted

```bash
ame security usb
```

Un dispositivo USB puede hacerse pasar por un teclado y escribir solo, y un keylogger físico puede
colocarse entre un teclado real y el equipo. La protección USB permite lo que está conectado cuando la
configura y bloquea todo lo nuevo hasta que lo permita con `ame security usb allow`. Está desactivada
de forma predeterminada, porque un equipo que bloqueara su propio teclado en el primer arranque sería
inutilizable.

### Protección del navegador

```bash
ame security browser
```

Una extensión ve todas las páginas que abre, y así es como llegan la mayoría de los ladrones de
contraseñas. Con la protección del navegador activada, los navegadores solo instalan las extensiones
de una lista: los gestores de contraseñas Bitwarden, 1Password, Proton Pass y KeePassXC, y las
extensiones que añada con `ame security browser allow <id>`. Además, las páginas web no pueden acceder
a dispositivos USB, serie, HID ni Bluetooth. Cubre Firefox, Brave, Chrome, Chromium y Edge, instalados
ahora o más adelante, para todas las cuentas del equipo. Los demás navegadores no están cubiertos.

Permita las extensiones que usa antes de activarla. Firefox elimina las que no están en la lista, con
su configuración, la próxima vez que se inicia; los demás navegadores desactivan las suyas. Firefox
muestra el ID de cada extensión en `about:support`, en Complementos, y los demás en su página de
extensiones con el modo de desarrollador activado. Los temas, diccionarios y paquetes de idioma de
Firefox no se tocan.

Lo que permitió está en `/etc/amethystora/browser-extensions`, un ID por línea. Para retirar uno,
quite su línea y vuelva a ejecutar `ame security browser on`. Está desactivada de forma
predeterminada: Firefox viene exactamente como lo compila Fedora, y lo que puede instalar lo decide
usted, no la imagen.

### Protección de red

```bash
ame security settings network
```

Suricata inspecciona cada conexión que hace y recibe este equipo con las reglas Emerging Threats Open,
que descarga cada día:

- **`watch`** informa de lo que reconoce y no bloquea nada. Empiece por aquí: una semana así muestra
  qué estorbaría el bloqueo.
- **`block`** además corta las conexiones a malware conocido y sus servidores de mando, exploits,
  páginas de phishing y criptomineros, y a las direcciones de las listas de bloqueo de Spamhaus y
  DShield. Lo que las reglas reconocen con menos certeza solo se notifica.

Cada conexión bloqueada genera una notificación. **Red**, en la aplicación **Seguridad**, lista lo que
se bloqueó y se detectó, igual que `ame security connections`. Si una conexión era suya y la quería,
**Permitir**, o `ame security connections allow <rule>`, excluye esa regla en este equipo, y
`ame security connections block <rule>` la vuelve a poner.

Pase lo que pase con ella, sus conexiones siguen funcionando: mientras Suricata se inicia, se
reinicia, se queda atrás o se detiene, pasan sin inspeccionar en lugar de no pasar. Una conexión
cifrada se inspecciona hasta su negociación inicial, el nombre del servidor y el certificado, porque
lo que sigue no se puede leer. Su registro guarda lo que reconoció y nada más, nunca una lista de los
sitios que visita. Inspecciona las conexiones propias de este equipo, no lo que reenvía para máquinas
virtuales o contenedores ejecutados como root, y ocupa unos cientos de megabytes de memoria. Está
desactivada de forma predeterminada: bloquear algo es una decisión sobre su propio tráfico, y le
corresponde a usted.

### Reasignación de teclas

Input Remapper se ejecuta como root y lee cada tecla que se escribe en cada aplicación. Eso es lo que
necesita la reasignación, y en todo lo demás equivale a un keylogger, así que viene desactivado. Si
reasigna teclas o botones del ratón, actívelo con `ame security input-remapper`.
