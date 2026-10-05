# Games and Android apps

Neither comes set up, because each needs something the image keeps from apps that do not need it.
One command each sets them up, says what it changes first, and takes it all away again. The switches
on [Control](control.md)'s **Apps** page open the same commands in a terminal.

## Games

```bash
ame apps gaming
```

This installs **Steam** from Flathub, with **ProtonPlus**, which adds other versions of Proton, and
two tools Steam's games can use: the **MangoHud** overlay and Valve's **gamescope** compositor. It also
offers **Heroic**, for the Epic, GOG and Amazon stores, and **Lutris**, for games from anywhere else.

Every Flatpak is refused X11 on this desktop, because an app on X11 can read what you type into other
X11 apps ([what Flatpak apps may not do](software.md#what-flatpak-apps-may-not-do)). Steam and the
Windows games it runs through Proton draw on nothing else, so X11 is granted back to Steam and the
launchers you add, for your account alone. The Security app's **Apps** page lists it with every other
permission ([App permissions](security.md#app-permissions)).

In a game's **Properties** in Steam, under **Launch Options**:

| Launch option | Does |
| --- | --- |
| `mangohud %command%` | The overlay: frame rate, frame times, temperatures |
| `gamemoderun %command%` | The CPU's performance mode while the game runs, through GameMode |
| `gamescope -f -- %command%` | The game in its own compositor, full screen, which helps with games that dislike Wayland |

Game controllers work without anything to set up: Xbox, PlayStation, Nintendo and Steam controllers,
8BitDo, and the rest that Steam knows of. **Add another launcher** adds Heroic or Lutris later, and
**Take it all away** uninstalls them all, with their games, and takes back what was granted:

```bash
ame apps gaming launchers
ame apps gaming off
```

## A faster CPU scheduler for games

The kernel decides which program runs on which CPU core and for how long. Its own scheduler suits
nearly everything. A sched-ext scheduler is a small program the kernel hands that job to, and one
made for a kind of work can do it better:

```bash
ame system scheduler
```

| Scheduler | For |
| --- | --- |
| `kernel` | Everything: the kernel's own, and the default |
| `lavd` | Games, smooth while other work runs: made for gaming handhelds and laptops |
| `bpfland` | A desktop that stays responsive while something heavy builds or renders |
| `flash` | Steady timing, for audio and music work |

Control's **System** page offers the same four. The choice holds after a restart, and `ame system
scheduler kernel` puts the kernel's own back. If a
sched-ext scheduler stops, the kernel takes over again by itself, so the worst one can do is make
things slower. A kernel built before Fedora's dwarves 1.32 cannot load the current schedulers; the
command says so and leaves the kernel's own in place.

## Android apps

```bash
ame apps android
```

**Waydroid** runs Android, LineageOS 20, in a container beside your desktop, and the Android apps you
install appear in the app grid like any other. Setting it up downloads Android from Waydroid's servers,
about a gigabyte. It comes without Google's apps and Play Store, whose apps come with Google's own
terms: get apps from F-Droid, or install an `.apk` you downloaded:

```bash
waydroid app install ~/Downloads/some-app.apk
```

Open **Waydroid** from the app grid; the first start takes a minute. Its container service runs as
root, so it is only on once you set it up, and you can stop it when you are not using it:

| Command | Does |
| --- | --- |
| `ame apps android start` | Start Android, and open it |
| `ame apps android stop` | Stop it, until you start it again |
| `ame apps android off` | Remove Android, with every app and everything saved in it |

Waydroid cannot draw with NVIDIA's driver, so on the NVIDIA images Android draws in software: fine for
most apps, slow for games.
