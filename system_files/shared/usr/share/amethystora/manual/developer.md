# Developer mode

`amethystora-dx` is the same desktop with a developer's workshop on top: container engines,
virtual machines, VS Code, and the profiling tools to find out why something is slow.

The idea behind it: your development environment should not be your operating system. Toolchains,
language runtimes and databases live in containers that are described in the project's own
repository, so the project builds the same on your machine, a colleague's Mac and in CI, and the
system underneath stays clean enough to update without a second thought.

## Turning it on

Switch to the dx image, and restart:

```bash
sudo bootc switch --enforce-container-sigpolicy ghcr.io/iarsslen/amethystora-dx:stable
```

If you have [layered packages](software.md#layering-the-last-resort), use
`sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/iarsslen/amethystora-dx:stable` instead,
which keeps them. Switching back to `amethystora` works the same way.

On its first boot the dx image adds every administrator account to the `docker`, `incus-admin` and
`libvirt` groups. If `docker ps` says permission denied, log out and back in once.

## What it adds

| Tool | For |
| --- | --- |
| VS Code | The editor, with the Dev Containers, Remote SSH and Containers extensions installed. Its colours follow the [theme](themes.md). |
| Docker Engine | With buildx and compose. The default for Dev Containers. |
| Podman | With `podman-compose` and `podman machine`. Always there, rootless, and the Podman socket is on. |
| Incus | System containers and virtual machines, managed like cloud instances |
| libvirt and virt-manager | Virtual machines with QEMU and KVM |
| Sysprof, bcc, bpftrace, bpftop, trace-cmd | Profiling and tracing, from the whole system down to one function |
| android-tools | `adb` and `fastboot` |
| ROCm | GPU compute on AMD graphics |
| flatpak-builder | Building Flatpaks |

## Dev Containers

A dev container is a `.devcontainer/devcontainer.json` in the project: the image, the tools and the
editor extensions the project needs. Open the project in VS Code and it offers to reopen inside the
container. Everything the project installs stays in there.

- [Dev Containers in VS Code](https://code.visualstudio.com/docs/devcontainers/containers): skip the
  installation part and start from the tutorial.
- [The specification](https://containers.dev), which JetBrains IDEs and the `devcontainer` command line
  tool follow too.

To use Podman instead of Docker, add these to VS Code's settings:

```json
"dev.containers.dockerPath": "podman",
"dev.containers.dockerComposePath": "podman-compose"
```

If a container cannot read a mounted folder because of SELinux, relabel the folder rather than
turning SELinux off: `restorecon -R -v ~/code/myproject`.

## Other editors

- **JetBrains:** `ujust jetbrains-toolbox` installs the JetBrains Toolbox into your home, which then
  installs and updates the IDEs. The IDEs' Flatpaks are not recommended.
- **Neovim, Helix and friends:** `brew install neovim`, and `brew install devcontainer` for the dev
  container command line.

## Kubernetes and the cloud

Install the command line tools with Homebrew, so they stay current without touching the image:

```bash
brew install kubectl helm k9s kind
```

`kind` runs a whole Kubernetes cluster in Docker containers, which is the quickest way to try
something against a real cluster.
