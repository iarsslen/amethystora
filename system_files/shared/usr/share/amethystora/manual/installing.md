# Installing

Amethystora is installed by switching an existing Fedora Atomic system to it. The switch replaces
the operating system image and keeps everything in `/home`, `/etc` and `/var`.

## Before you start

- **Install Fedora Silverblue** (or another Fedora Atomic desktop) if the machine does not run one
  yet. Choose **disk encryption** in the installer: it cannot be turned on afterwards, and it is what
  keeps your files safe if the machine is lost or stolen.
- **Back up** anything you cannot lose. Switching is safe, but a backup always is.
- Packages you layered onto the old system with `rpm-ostree install` do not come along. Flatpaks,
  Homebrew and containers do.

## Switch

```bash
sudo bootc switch ghcr.io/iarsslen/amethystora:stable
```

Then restart. On the first boot a service stages the switch to signature-checked updates by itself,
and from the restart after that, an update is only accepted if it carries Amethystora's signature.

## Pick an image

| Image | For |
| --- | --- |
| `ghcr.io/iarsslen/amethystora` | The standard desktop |
| `ghcr.io/iarsslen/amethystora-dx` | Developers: adds Docker, Incus, libvirt, VS Code and more ([Developer mode](developer.md)) |
| `ghcr.io/iarsslen/amethystora-nvidia-open` | The standard desktop with NVIDIA's open kernel driver |
| `ghcr.io/iarsslen/amethystora-dx-nvidia-open` | Developer mode with NVIDIA's open kernel driver |

The NVIDIA images are paused at the moment. Check that the tag you want exists before switching to
one.

## Pick a stream

Every image comes in three streams, set by the tag after the colon:

| Tag | For |
| --- | --- |
| `stable` | Everyone. Built weekly, with the kernel held back to Fedora CoreOS's, which lags a little behind Fedora's so that kernel regressions are caught first. |
| `latest` | The newest Fedora has, rebuilt whenever Amethystora changes. |
| `beta` | Testing what comes next. Expect rough edges. |

You can move between images and streams at any time; [Updates](updates.md#switching-streams-and-images)
shows how.

## After the first boot

Go through [Getting started](getting-started.md). The one step not to skip is enrolling the Secure
Boot key, if Secure Boot is on.
