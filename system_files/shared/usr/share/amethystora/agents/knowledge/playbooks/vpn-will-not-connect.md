# A work or school VPN will not connect

## Symptom

A VPN from an employer or school (Cisco AnyConnect, Fortinet, GlobalProtect, Pulse or Ivanti, SSTP, IPsec,
L2TP/IPsec) fails in **Settings → Network → VPN**: it asks again for the password, stops at "connecting",
says the connection failed, or connects and then no site or company name loads.

## Look

- `state security`: the `stricter` check names `kernel strict`, which blocks the IPsec modules.
- `logs` unit `NetworkManager.service`; then, for the plugin that failed:
  `journalctl --no-hostname _COMM=nm-l2tp-service _COMM=ipsec _COMM=pluto _COMM=charon _COMM=kl2tpd _COMM=xl2tpd _COMM=pppd`
  (the L2TP/IPsec plugins' own advice), or `logs` identifier `nm-sstp-service`, `nm-openconnect-service`,
  `nm-fortisslvpn-service` (up to Fedora 44: Fedora 45 retired the Fortinet and vpnc plugins).
- `nmcli connection show --active`, `nmcli -f NAME,TYPE,VPN.VPN-TYPE connection show`
- `lsmod | grep -E 'l2tp|esp4|ppp'`, `modprobe -n -v net-pf-16-proto-16-family-l2tp`
- `resolvectl status`, `/usr/libexec/amethystora-dns status`
- `ausearch -m avc -ts recent` (root) for SELinux denials

## Causes on Amethystora

1. **IKEv1.** Libreswan refuses IKEv1 by default (`ikev1-policy=drop`, upstream's choice since version 5.0);
   most routers and older Windows servers offering L2TP/IPsec speak nothing else. Tell: the journal says
   "global ikev1-policy does not allow IKEv1 connections".
2. **`ame security kernel strict` is on.** It blocks `esp4` and `esp6`, which every IPsec VPN (Libreswan,
   L2TP/IPsec) needs. Tell: the setting is on; the journal says the ESP module could not be loaded.
3. **L2TP's kernel modules.** The image lets `l2tp_netlink` and `l2tp_ppp` load on demand; a machine
   where someone put the `blacklist` lines back in `/etc/modprobe.d` (`l2tp_ppp-blacklist.conf`) stops
   `kl2tpd`. Tell: `kl2tpd` or `pppd` logs a missing module or netlink family.
4. **A certificate in the home folder (L2TP).** SELinux denies `dac_override` to `nm-l2tp-service` when the
   VPN's certificate is kept in a home folder (Fedora bug 2440925, open). Tell: an `avc: denied` line for
   `nm-l2tp-service`.
5. **Encrypted DNS and the VPN's own names.** The company's names resolve only through the VPN's servers.
   Names the VPN pushes keep working with `ame security dns` on; a VPN that pushes none does not. Tell:
   the tunnel is up, an address pings, a company name does not resolve (`resolvectl query NAME`).
6. **The wrong client for the server.** A FortiGate may answer to OpenConnect's Fortinet protocol or to
   the Fortinet plugin but not both (realms, SAML login); Cisco and GlobalProtect need OpenConnect's
   protocol chosen in the dialog. Tell: the login page or error names the product.
7. **PPTP.** Not in the image, deliberately (MS-CHAPv2 is broken); its VPN type is missing from the list.
8. **The server's side.** An expired password, a certificate that changed, a second factor: the log says
   authentication failed, not that the plugin cannot start.

## Fix

### IKEv1 (L2TP/IPsec to a router or old server)

Prefer asking the administrator for IKEv2. If the server offers nothing else, the user (root) allows it for
this machine by uncommenting the shipped line in `/etc/ipsec.conf`:
`sudo sed -i 's/^#ikev1-policy=accept/ikev1-policy=accept/' /etc/ipsec.conf`. Never do it for them.

### Strict kernel mode

The user runs `ame security kernel standard` (root), then restarts. Never do it for them: it loosens protection.

### L2TP's modules

A machine whose `/etc/modprobe.d` has `l2tp_ppp-blacklist.conf` or `l2tp_netlink-blacklist.conf` back: the
user (root) comments the `blacklist` line, or removes the file, and reconnects.

### A certificate in the home folder

Move it to `/etc/pki` (root), or use a password for that VPN. The bug is Fedora's, not the image's.

### DNS

With a VPN that pushes no names, the user may use the VPN's resolver by hand
(`nmcli connection modify NAME ipv4.dns SERVER ipv4.dns-search DOMAIN`) or `ame security dns pause` (root)
to test. Never turn encrypted DNS off for them.

### Another client

Try the other plugin for the server (OpenConnect's Fortinet protocol or the Fortinet plugin). Add the VPN
again in **Settings → Network → VPN**; the agent does not handle its password.

## Verify

- `nmcli connection show --active` lists the VPN; `ip route` shows its routes; a company name resolves
  (`resolvectl query NAME`).
- The journal command above shows no new error.

## Undo

- `nmcli connection delete NAME` removes a VPN made by hand; `nmcli connection down NAME` ends it.
- Put the `#` back in front of `ikev1-policy=accept` in `/etc/ipsec.conf` (root), and the `blacklist` line
  in a module's file.
- `ame security kernel strict` (root) turns the stricter kernel mode back on; the agent may run it when the
  user asks.
