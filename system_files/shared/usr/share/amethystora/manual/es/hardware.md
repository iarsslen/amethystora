# Hardware

Amethystora funciona mejor en hardware que Linux admite bien: gráficos Intel y AMD, y los portátiles
que sus fabricantes certifican para Linux. La mayoría de las cosas funcionan en cuanto se conectan;
esta página trata de las que necesitan algún paso por su parte.

## Secure Boot

Deje Secure Boot activado. Con él, el equipo solo arranca un núcleo que ha comprobado, y el
[bloqueo](security.md) del núcleo tiene en qué apoyarse.

Los módulos del núcleo incluidos en la imagen, para las bases de conexión DisplayLink y las cámaras
virtuales, están firmados con la clave propia de Amethystora, y hay que decirle al firmware una vez
que confíe en ella:

```bash
ame security secure-boot
```

Reinicie, y aparecerá una pantalla azul antes de que arranque el sistema: el gestor de MOK. Elija
**Enroll MOK**, luego **Continue**, luego **Yes**, y escriba la contraseña `amethystora`. La pantalla
usa la distribución de teclado de EE. UU. (QWERTY) sea cual sea la suya, lo que importa si su teclado
tiene las letras en otro sitio. `ame security status` le indica si las claves están registradas.

Si Secure Boot está desactivado, una notificación lo indica una vez. Actívelo en la configuración del
firmware del equipo y después ejecute el comando anterior.

## Gráficos

- **Intel y AMD** funcionan desde el primer momento. La imagen para desarrolladores añade ROCm para el
  cálculo en GPU con AMD.
- **NVIDIA** necesita las imágenes `-nvidia-open`, que llevan el controlador de núcleo abierto de NVIDIA ([Instalación](installing.md#pick-an-image)).
  El controlador de NVIDIA se compila para el equipo y se firma con su propia clave, así que las
  imágenes NVIDIA no usan el bloqueo del núcleo.
- **¿Instaló la imagen sin el controlador de NVIDIA en un equipo con tarjeta NVIDIA?** No hay
  instalador para las imágenes NVIDIA, así que así es como empiezan la mayoría de los equipos con
  NVIDIA. Unos minutos después del primer arranque, una notificación ofrece **Switch images…**, que
  abre `ame system rebase` con la imagen `-nvidia-open` correspondiente; solo acepta imágenes firmadas
  y pregunta antes de cambiar. Una imagen NVIDIA en un equipo sin tarjeta NVIDIA ofrece la imagen sin
  el controlador, que mantiene el bloqueo activado. Nada cambia por sí solo, el aviso se da una vez
  por equipo, y **Don't ask again** lo detiene para siempre.

## Bases de conexión y pantallas

- Las **bases de conexión DisplayLink** funcionan con el controlador incluido en la imagen. Con Secure
  Boot activado, la base no muestra nada hasta que se registra la clave anterior.
- El **brillo de los monitores externos** se puede ajustar desde la línea de comandos con `ddcutil`,
  en los monitores que lo admiten.

## Discos

- El **cifrado** se elige al instalar y no se puede añadir después. Una vez activado,
  `ame security disk-unlock` permite que el TPM desbloquee el disco al arrancar en lugar de que usted
  escriba la frase de contraseña ([Seguridad](security.md#unlock-the-disk-with-the-tpm)).
- **ZFS** está disponible en el canal `stable`.

## Impresoras y escáneres

La mayoría de las impresoras se encuentran en la red y funcionan sin más, sin controlador. Para las
demás se incluyen controladores para impresoras HP y para muchas impresoras Brother y láser antiguas.
Añada una impresora en **Configuración → Impresoras**.

## Teléfonos

- **Android:** GSConnect enlaza el teléfono con el escritorio: notificaciones, transferencia de
  archivos, un portapapeles compartido y mensajes. Instale KDE Connect en el teléfono y emparéjelos
  desde la configuración rápida.
- **iPhone:** conéctelo y confíe en el equipo desde el teléfono; sus fotos y archivos aparecen en
  Archivos.

## Teclados, ratones y llaves de seguridad

- **Ratones para juegos:** el servicio que los configura está incluido; instale **Piper** desde Bazaar
  para cambiar los botones, la iluminación y la resolución.
- **Reasignar teclas:** `ame security input-remapper` activa Input Remapper ([Seguridad](security.md#key-remapping)
  explica por qué empieza desactivado).
- Las **llaves de seguridad FIDO2** pueden sustituir a su contraseña: [Seguridad](security.md#security-keys).

## Portátiles

Los portátiles Framework reciben sus correcciones conocidas en el primer arranque, para la
suspensión, el audio y el teclado, y el modelo de 13 pulgadas, un tamaño de texto adecuado a su
pantalla. Mantenga el firmware al día en todos los equipos: **Actualizaciones** muestra lo que hay, o
en una terminal:

```bash
fwupdmgr get-updates
fwupdmgr update
```

[Firmware](updates.md#firmware) tiene más información.

## Cámaras

Las cámaras virtuales (la de OBS, por ejemplo) funcionan sin instalar nada, gracias al módulo loopback
incluido en la imagen.
