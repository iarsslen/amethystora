# The VM lab

A virtual machine for trying an Amethystora image as it boots: UEFI with Secure Boot and Microsoft's keys, a
TPM 2.0, GNOME on a 1280×800 screen. An agent drives it through an MCP server, `server.mjs`; a person can
drive it with the same calls.

Nothing of the lab is in the image. Commands reach the guest through `agent.py`, which QEMU hands to systemd as
a credential at boot (SMBIOS type 11) and which runs from `/run` until the VM shuts down. It answers on a
virtio-serial port no other machine can reach. The screen, keys, mouse and snapshots go through QEMU's own
monitor. The image is used as it is published, so the security watcher may say that a unit it does not know
ran: that is the lab's helper.

## Setting it up

The lab is a privileged Fedora container, `amevm`, with QEMU, KVM, OVMF and swtpm. It needs Docker or
Podman on Linux, or Docker Desktop on Windows (nested virtualization in WSL 2 gives it `/dev/kvm`).

```bash
MSYS_NO_PATHCONV=1 bash tests/vm/setup.sh   # MSYS_NO_PATHCONV only in Git Bash on Windows
```

`setup.sh` builds the lab's image and starts the container again. Disks and VMs stay in the volume
`amevm-vm`, pulled images in `amevm-storage`; VMs that were running are stopped. Run it again after changing
anything here.

To give the server to Claude Code, for this checkout only:

```bash
claude mcp add amethystora-vm --scope local -- docker exec -i amevm node /opt/amethystora-vm/server.mjs
```

The tools appear in the next session.

## Using it

1. `disk_build` installs an image onto a disk with `bootc install to-disk` (btrfs, as the installer ISO
   makes it), about 10 minutes. `disk_list` says when it is ready.
2. `vm_start` starts a VM on an overlay of that disk; `vm_wait` returns once the boot is over.
3. `vm_exec` runs a command as root, as an account, or in that account's graphical session (`session`).
   `vm_write` and `vm_read` move files.
4. `vm_screenshot`, `vm_keys` and `vm_mouse` see and use the desktop; `vm_serial` is the serial console.
5. `vm_snapshot` saves and loads the whole machine; `vm_stop` and `vm_delete` end it.

A new disk has no account and starts GNOME's first-run setup. To log in as a test account:

```bash
useradd -m -G wheel tester && echo tester:tester | chpasswd
printf '[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin=tester\n' >/etc/gdm/custom.conf
install -d -o tester -g tester ~tester/.config && touch ~tester/.config/gnome-initial-setup-done
systemctl restart gdm
```

The VM has 4 GB of memory and 4 processors unless `vm_start` says otherwise. Under nested virtualization
GNOME draws in software and is slow: turn its animations off for screenshots.
