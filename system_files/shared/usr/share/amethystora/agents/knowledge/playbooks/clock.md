# The clock is wrong

## Symptom

The time or date in the top bar is wrong, off by whole hours after Windows ran, or in the wrong time zone;
or sites, updates and signatures fail with certificate errors ("not yet valid", "expired") because the
clock is off.

## Look

- `state health` (finding `time-sync`), `state security-settings` with filter `time` (authenticated time).
- `logs` unit `chronyd.service`.
- `timedatectl`: local and universal time, RTC time, time zone, `System clock synchronized`,
  `NTP service`, `RTC in local TZ`
- `systemctl status chronyd.service`, `systemctl is-enabled systemd-timesyncd.service`
- `chronyc tracking`, `chronyc -N sources -v`. With `ame security time` on, both need `sudo`: its
  configuration closes chrony's command port. `sudo chronyc -N authdata` shows each server's NTS key
  exchange.

## Causes on Amethystora

The clock is set by chrony (`chronyd.service`), as on Fedora Workstation; systemd-timesyncd ships but is
not used.

1. **Authenticated time is on, and the network blocks it** (`ame security time`, off as shipped). It
   replaces `/etc/chrony.conf` with `/usr/share/amethystora/hardening/chrony.conf`: NTS servers only, three
   of which must agree, never one a network suggests. A network that blocks TCP port 4460, or the servers,
   leaves the clock unsynced. Tell: `time` on; `sudo chronyc -N sources` has no `*` line; `authdata` shows
   no cookies.
2. **Dual boot with Windows.** Windows keeps the hardware clock in local time, Linux in UTC, so each moves
   the other by the time zone's offset. Tell: wrong by exactly that offset after Windows ran;
   `RTC in local TZ: no`.
3. **The time zone is wrong.** Universal time is right, local time is not. Tell: `timedatectl`'s time zone;
   GNOME's automatic time zone (`gsettings get org.gnome.desktop.datetime automatic-timezone`) needs
   location services on.
4. **Synchronisation is off.** Tell: `NTP service: inactive`, `chronyd.service` disabled or masked, or
   systemd-timesyncd enabled beside it, two programs setting one clock.
5. **No way to a time server**: no network, a login page not passed yet, or encrypted DNS behind such a
   page, which resolves nothing. Tell: every source `?` in `chronyc sources`; `resolvectl query` with a
   server's name from `chronyc -N sources` fails.
6. **A flat battery on the board.** The clock is far off after every cold start and right once synced.
   Tell: `timedatectl`'s RTC time far from universal time after the machine was unplugged.

## Fix

### 1. Authenticated time

Try another network first. Otherwise the user runs `ame security time off` (root): the clock then also
follows Fedora's pool and servers the network names, which can set it to anything they like. Applies at
once.

### 2. Dual boot

- Better: Windows keeps UTC too. The user sets, in Windows, the DWORD `RealTimeIsUniversal` = 1 under
  `HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation`, and restarts Windows.
- Or here: `timedatectl set-local-rtc 1 --adjust-system-clock` (root). systemd warns that a hardware clock
  in local time goes wrong around daylight-saving changes.

### 3. Time zone

**Settings › System › Date & Time**, or `timedatectl list-timezones`, then
`timedatectl set-timezone Region/City` (an administrator's password may be asked). Note the old zone first.

### 4. Synchronisation off

`timedatectl set-ntp true` (root), which starts chronyd; `sudo systemctl unmask chronyd.service` (root)
first if it was masked. With systemd-timesyncd enabled by hand:
`sudo systemctl disable --now systemd-timesyncd.service` (root).

### 5. No way to a server

Get online, or pass the login page. With encrypted DNS on, the user runs `ame security dns pause` (ten
minutes, a password). Then `sudo chronyc makestep` (root) sets the clock at once rather than slowly.

### 6. The battery

The firmware's battery is replaced by the user; until then the network sets the clock after each start.

## Verify

- `/usr/libexec/amethystora-doctor --only time-sync` (exits 0 when the clock is synchronised).
- `timedatectl`: `System clock synchronized: yes`, the right time zone, and after Windows the right hour.
- `chronyc tracking`: a small `System time` offset.

## Undo

- Authenticated time back: `ame security time on` (root), which the agent may run when the user asks.
- `timedatectl set-local-rtc 0 --adjust-system-clock` (root); in Windows, delete `RealTimeIsUniversal`.
- `timedatectl set-timezone` with the zone noted before.
- `timedatectl set-ntp false` (root) turns synchronisation off again; only if the user wants that.
