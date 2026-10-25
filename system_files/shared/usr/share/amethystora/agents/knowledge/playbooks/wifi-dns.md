# Wi-Fi drops, no internet, or names do not resolve

## Symptom

Wi-Fi disconnects or will not connect; it says connected but nothing loads; sites say "server not found"
while 9.9.9.9 answers; a hotel or café login page never appears; one site or app cannot connect while the
rest work; or printers and the phone are not found.

## Look

- `state security`: the checks `encrypted-dns-paused`, `network`, `firewall`, `home-networks`.
- `state security-settings` filter `network` (`NETWORK`), then `firewall-away`, then `time`.
- `logs` unit `NetworkManager.service`, unit `systemd-resolved.service`; `logs` identifier `kernel`, grep
  `wlan|wlp|firmware|deauth`.

Then:

- `nmcli device status`, `nmcli networking connectivity check` (`portal`: a login page)
- `resolvectl status`, `resolvectl query example.org`, `ping -c 3 9.9.9.9`
- `/usr/libexec/amethystora-dns status`, `/usr/libexec/amethystora-mac status`
- `firewall-cmd --get-active-zones`, `nmcli -g connection.zone connection show NAME` (empty: the default)
- `ame security connections` (root), or `/var/lib/amethystora/security/network.json` (wheel may read it)
- `timedatectl`

## Causes on Amethystora

1. **Encrypted DNS on a network that blocks it.** With `ame security dns` on, every name goes over
   DNS-over-TLS (port 853) to one resolver; a network that blocks 853 resolves nothing. Tell: the helper
   says `on`, `ping 9.9.9.9` answers, `resolvectl query` fails.
2. **A login page behind encrypted DNS.** The page cannot load. Tell: the connectivity check says
   `portal`; the session's `amethystora-dns-portal.service` should have offered a pause.
3. **A new address on each network.** With `ame security mac` on or away, a network that admits only
   registered devices, or a router's reservation, refuses the machine: it connects but gets no address or no
   internet, on that network only. Tell: the helper says `on` or `away`; with `away`, a network named home
   (`/etc/amethystora/firewall-home`) is not affected.
4. **Network protection blocked it.** With `NETWORK` at `block`, Suricata cuts connections its rules call
   malware, phishing or block-listed: one site or app fails. Tell: the host and rule number in
   `ame security connections`. It fails open: a stopped `amethystora-ips.service` never cuts the network.
5. **A firewall zone, for what comes in.** Zones never block going out. The default, `amethystora`, lets
   in printer discovery and Windows shares; `amethystora-home` adds phone pairing; with
   `ame security firewall-away` on, `amethystora-away` lets in neither. Tell: printers, casting or the
   phone are not found.
6. **The clock.** With `ame security time` on, a network that blocks NTS (port 4460) leaves the clock
   unsynced; far enough off, every secure site fails with certificate errors. Tell: `timedatectl`.
7. **Tailscale.** An exit node or its DNS carries the traffic: `tailscale status`.
8. **The Wi-Fi itself.** Weak signal, power saving, or the driver and its firmware (the kernel log). No
   Wi-Fi device in `nmcli device status`: no driver for the card. Began with an update: `rpm-ostree db diff`.

## Fix

### DNS blocked, or a login page

The user runs `ame security dns pause` (root): for ten minutes the network's servers answer, in plain text.
Where it is always blocked, the user may choose `ame security dns off` (root). Never do either for them.

### Address per network

For that network only, the user sets **Cloned Address** to **Permanent** under **Identity** in its
Settings, or, with a yes, `nmcli connection modify NAME 802-11-wireless.cloned-mac-address permanent`
(`ethernet.cloned-mac-address` when wired), then reconnects. For a network that is the user's own, naming it
home (`ame security home-networks`) does the same under `ame security mac away`, before `ame security mac
off` (root), which is theirs.

### Network protection

When the connection was wanted, the user runs `ame security connections allow RULE` (root): that rule is
left out on this machine.

### Zones

At home, the user may name the network with `ame security home-networks` (root).
`ame security firewall-away off` (root) is theirs.

### Clock

The user runs `ame security time off` (root), or uses a network that lets NTS through.

### Tailscale

Turn its exit node off, or `ame system tailscale off` (root).

### The Wi-Fi

`nmcli device wifi rescan`, then `nmcli connection up NAME`. Power saving:
`nmcli connection modify NAME 802-11-wireless.powersave 2`, then reconnect. Broken by an update: the boot
menu's second entry, then `bootc rollback` (root) (restart), and `ame report`.

## Verify

- `resolvectl query example.org` answers; `nmcli networking connectivity check` says `full`.
- `state security`: no `encrypted-dns-paused` once the pause is over.
- `ame security connections`: nothing new blocked for that host.

## Undo

- A pause ends by itself after ten minutes (`amethystora-dns-resume.timer`), or `ame security dns resume`
  (root).
- `nmcli connection modify NAME 802-11-wireless.cloned-mac-address ""` returns to the machine's setting;
  `nmcli connection modify NAME 802-11-wireless.powersave 0`.
- `ame security connections block RULE` (root) puts a rule back.
- `ame security mac on`, `ame security time on`, `ame security firewall-away on` (root) turn protection on:
  the agent may run them when the user asks. Encrypted DNS comes back with its resolver, such as
  `ame security dns quad9` (root).
