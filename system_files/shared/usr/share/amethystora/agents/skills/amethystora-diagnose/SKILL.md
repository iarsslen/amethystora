---
name: amethystora-diagnose
description: Find out why something broke on an Amethystora machine - a crashed program, a failed service, a desktop that misbehaves, or a problem that started after an update - without changing anything. Use when the user asks why something crashed, froze, failed or stopped working, or when started by `amethystora-agent diagnose`.
---

# Diagnosing a problem on Amethystora

Read the `amethystora` skill too: it says what may be changed on this system and where.

## Rules

- **Change nothing while diagnosing.** Read logs and state only. The result is a diagnosis and a
  proposed fix; the user decides whether to apply it, and you apply only what they approve.
- **Evidence first.** Quote the log lines, the stack frames or the command output your conclusion
  rests on, and say how sure you are. Never present a plausible cause as an observed one.
- **Leave the system as you found it.** A core file you extract, a tool you install into a
  container, a temporary file: remove it when you are done, and say that you did.
- **Logs hold personal data** (paths, host names, account names, sometimes URLs). Never send them
  anywhere, and show the user any text before it goes into a bug report.

## What the account can read

- `kernel.dmesg_restrict` is on, so read the kernel log with `journalctl -k`, not `dmesg`.
- The system journal is readable by accounts in `wheel`. If `journalctl -b` says it cannot see
  system messages, say so and ask before using `sudo`.
- `kernel.yama.ptrace_scope` is 1: attaching a debugger to a running process is refused. Work from
  core dumps instead.
- Core dumps of setuid programs are not kept (`fs.suid_dumpable = 0`).

## Method

1. **Pin down what failed and when.** Start from what the prompt gives you.
   - A crash: `coredumpctl list --no-pager --since=-7d`, then `coredumpctl info <pid> --no-pager`.
     The stack trace in it was recorded at crash time; that is often enough.
   - A service: `systemctl status <unit>` or `systemctl --user status <unit>`, then
     `journalctl -b -u <unit>` or `journalctl --user -b -u <unit>`.
   - Otherwise: `systemctl --failed`, `systemctl --user --failed`, `journalctl -b -p err --no-pager`.
     A freeze or a sudden reboot shows in the previous boot: `journalctl --list-boots`, then
     `journalctl -b -1 -p warning -n 200 --no-pager`.
2. **Find what owns it.** `rpm -qf <binary>` for the image. A path under `/app` or a
   `flatpak-*.scope` is a Flatpak: `flatpak info <app-id>`. Under `/home/linuxbrew` it is Homebrew.
3. **Check whether an update caused it.** `rpm-ostree status` shows the booted and previous
   deployments; `rpm-ostree db diff` lists the packages that changed between them. A problem that
   began at the first boot of the new deployment and involves a package that changed is the likely
   cause, and `rpm-ostree rollback` is the likely fix.
4. **The desktop.** GNOME Shell and its extensions log to the user journal:
   `journalctl --user -b -g 'JS ERROR|Extension|gnome-shell' --no-pager`. List what is enabled with
   `gnome-extensions list --enabled`; an extension named in the errors is the first suspect.
5. **Hardware and drivers.** `journalctl -k -b -p warning --no-pager`. On the NVIDIA images,
   `rpm -qa 'kmod-nvidia*'` and whether the module loaded (`lsmod | grep nvidia`). Secure Boot
   refusing a module shows as "Key was rejected by service".
6. **SELinux**, when something is denied that should be allowed: `journalctl -b -t setroubleshoot`.
   The full audit log needs root (`sudo ausearch -m avc -ts recent`); ask first.
7. **A deeper backtrace**, only when the recorded one is not enough. gdb is not part of the image,
   so this installs something: ask first. `brew install gdb`, or a toolbox container
   (`toolbox create`, then `sudo dnf install gdb` inside it). Then `coredumpctl debug <pid>` and
   `bt full`; with debuginfod (`DEBUGINFOD_URLS`) gdb fetches the symbols itself. If you extract a
   core with `coredumpctl dump <pid> -o <file>`, delete the file afterwards.

## Report

Keep it short, in this order:

1. **What happened**: the program or service, when, and how (signal, exit code, error).
2. **Why**: the cause, the evidence for it, and your confidence. If the evidence does not settle
   it, say what would.
3. **Fix**: the commands you propose, which of them need `sudo` or a reboot, and how to undo each.
   Prefer the least invasive fix: a setting before a package, a rollback before a layered package.
4. **Report upstream?** Only when it is a bug and not local configuration, and only if the user
   agrees. Amethystora's own files (`/usr/bin/amethystora-*`, `/usr/share/amethystora`, the
   theme, keybindings, hardening) go to https://github.com/iarsslen/amethystora/issues. Other
   packages go to their own project, or to Fedora's Bugzilla for Fedora packages. Draft the report
   for the user to file; do not file it yourself.
