# NVIDIA: the driver does not load, or a black screen

## Symptom
A black screen after the boot logo on an NVIDIA laptop or desktop, often right after switching to an
NVIDIA image; or the desktop starts but slowly, on one screen only, without external monitors, and
`nvidia-smi` cannot talk to the driver.

## Look
- `state overview`: the image's flavor (`nvidia-open`, `nvidia-lts` or `main`), Secure Boot, and the GPU line:
  `NVIDIA (nvidia)` is the driver working, `NVIDIA (nouveau)` or `NVIDIA (no driver)` is not.
- `state security`: the checks `secure-boot`, `signing-keys` and `lockdown`.
- `logs` with identifier `kernel`, grep `nvidia|NVRM|Lockdown|rejected`, boot `0` (or `-1` for the start
  that failed).
- `/usr/libexec/amethystora-mok-status` (`enrolled`, `pending` or `not-enrolled` for each key),
  `mokutil --sb-state`, `lsmod | grep nvidia`, `modinfo -F signer nvidia`, `cat /proc/cmdline`,
  `rpm-ostree status`.
- `ame system drivers` (the driver check's last findings), `/usr/libexec/amethystora-gpu-check offer` (the
  image whose driver drives this card, if not this one), `cat /sys/bus/pci/devices/*/device` for the card's ID.

## Causes on Amethystora
1. **Secure Boot is on and the image's keys are not enrolled.** The NVIDIA driver is a module signed
   with a key of the machine owner (MOK), which the kernel trusts only once enrolled. Meanwhile the
   NVIDIA images' kernel arguments (`rd.driver.blacklist=nouveau`, `modprobe.blacklist=nouveau`,
   `initcall_blacklist=simpledrm_platform_driver_init`, from `/usr/lib/bootc/kargs.d`) turn off nouveau
   and the basic framebuffer that would otherwise stand in, so nothing draws. Usual after
   switching onto an NVIDIA image by hand; `ame system rebase` refuses to while the key is not enrolled. Tell: a key `not-enrolled`, and the kernel saying a
   module was rejected.
2. **The enrolment is pending.** The blue MOK manager screen was skipped, or its password mistyped: it
   reads a US (QWERTY) layout whatever the keyboard is. Tell: `pending`, `mokutil --list-new` lists it.
3. **Lockdown without Secure Boot.** The NVIDIA images leave the `lockdown=integrity` argument out on
   purpose; `ame security lockdown on` with Secure Boot off puts it in, and the machine's key is then
   not trusted. Tell: Secure Boot off, `lockdown=integrity` in `/proc/cmdline`.
4. **An NVIDIA card on an image whose driver does not drive it.** On the image without NVIDIA's driver,
   nouveau runs: slow, no CUDA. NVIDIA's open driver (`-nvidia-open`) drives Turing and newer only (device ID
   0x1E00 and up); Maxwell, Pascal and Volta (0x1340 to 0x1DFF: GeForce 900 and 10 series) need the closed
   driver of the 580 branch (`-nvidia-lts`); nothing NVIDIA makes now drives Kepler and older, which keep
   nouveau on the image without NVIDIA's driver. `amethystora-gpu-check.timer` offers the matching image
   once per machine, and **Don't ask again** stops it for good. Tell: `amethystora-gpu-check offer` names
   an image.
5. **Kernel arguments that did not follow a switch.** A machine with layered packages updates through
   rpm-ostree, which ignores kargs.d: an NVIDIA image may lack `nvidia-drm.modeset=1` and the nouveau
   blacklist, or the image without the driver may still carry the blacklist and show nothing. Tell:
   layered packages in `rpm-ostree status`, and `/proc/cmdline` not matching the image.

## Fix
### 1 and 2
Get a picture first: start the previous entry in the boot menu, the image before the switch; or press
`e` on the entry and delete `initcall_blacklist=simpledrm_platform_driver_init` for this one start (not
on a sealed image). On an encrypted disk a black screen may be the passphrase prompt it cannot show:
typing the passphrase and Enter continues. Then the user runs `ame security secure-boot` (root) and
restarts (restart): **Enroll MOK**, **Continue**, **Yes**, the password `amethystora`, **Reboot**. With
Secure Boot on, run `ame security secure-boot` before switching to an NVIDIA image, not after.

### 3
Best: turn Secure Boot on in the firmware (Control entry `bios` is an action: hand `ame system bios` to
the user with `run`) (restart), then fix 1. Otherwise the user runs `ame security lockdown off` (root)
(restart), which gives up kernel lockdown: root can then rewrite the running kernel.

### 4
`change` the Control entry `image` to the image `amethystora-gpu-check offer` names (`amethystora-nvidia-open`,
`amethystora-nvidia-lts`, the image without the driver, or their `-dx` ones on the developer image). It opens
`ame system rebase` in a terminal, which takes signed images only and asks first (root) (restart). With
Secure Boot on and the keys not enrolled, it offers `ame security secure-boot` instead and switches nothing:
enrol them, restart through the MOK manager, then switch.

### 5
On the NVIDIA image: `sudo rpm-ostree kargs --append-if-missing=rd.driver.blacklist=nouveau
--append-if-missing=modprobe.blacklist=nouveau --append-if-missing=nvidia-drm.modeset=1
--append-if-missing=initcall_blacklist=simpledrm_platform_driver_init` (root) (restart). On the image
without the driver, the same arguments with `--delete-if-present` (root) (restart).

## Verify
- `state overview` shows `NVIDIA (nvidia)`; `nvidia-smi` lists the card.
- `/usr/libexec/amethystora-mok-status` says `enrolled` for every key; `state security` has no
  `signing-keys` finding.
- `state health` no longer points to this playbook.

## Undo
- Back to the image without the driver: `ame system rebase` with the image name `state overview` shows,
  less `-nvidia-open` or `-nvidia-lts`, and the same stream (root) (restart).
- An enrolled key can stay: it only lets the image's own modules load.
- Lockdown: `ame security lockdown on` (root) (restart).
- Kernel arguments: the opposite flag of the same `rpm-ostree kargs` command (root) (restart). A
  one-time edit at the boot menu needs no undo.
