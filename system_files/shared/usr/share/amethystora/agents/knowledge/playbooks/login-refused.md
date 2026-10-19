# A login or sudo is refused

## Symptom
The account is locked after wrong passwords; the right password is refused at login, the lock screen or
`sudo`; a text console or SSH login is refused at some hours; SSH asks for a code, says "Too many
authentication failures", or does not connect; a finger or security key is ignored; a domain account
cannot log in.

## Look
- `state security`, and `state security-settings` filtered by `lockout`, `failed-logins` or
  `ssh-settings`: whether a switch was changed.
- `logs` with grep `pam_faillock|pam_malcontent|authentication failure|Too many`.
- `sudo faillock --user NAME` (root), `id NAME` (is `wheel` there?), `ame security addresses` (root),
  `/usr/libexec/amethystora-ssh-codes status`, `systemctl is-active sshd.service`, `timedatectl`,
  `realm list`, `sudo semodule -l | grep amethystora-pam` (root).

## Causes on Amethystora
1. **Account lockout.** Ten wrong passwords within 15 minutes lock the account for ten minutes,
   everywhere: login and lock screen, `sudo`, polkit, SSH; the right password is refused meanwhile.
   Tell: `faillock` lists ten recent failures.
2. **Parental Controls' allowed hours.** At the text consoles and over SSH only (`pam_malcontent` in
   `login` and `sshd`), an account outside its hours cannot log in, and a session there closes when its
   time runs out; the desktop locks instead. Tell: the journal names `pam_malcontent`.
3. **SSH one-time codes.** With `ame security ssh-codes` on, a password login over SSH also asks for a
   code; an account without codes of its own logs in with a key only. A wrong clock makes every code
   wrong. Tell: status `on`, no `~/.google_authenticator` for that account.
4. **The SSH server's settings.** Three tries per connection, so a client offering several keys fails
   before the password; root never logs in. Tell: `ssh -v` from the client.
5. **fail2ban.** Five failed SSH logins in ten minutes block the address for an hour, longer each time,
   up to a day. Tell: `ame security addresses` lists it.
6. **SSH does not connect.** The server is off, and the Amethystora firewall zone lets SSH in only over
   Tailscale. Tell: `sshd.service` inactive, or a refused or timed-out connection.
7. **sudo itself.** Not an administrator ("not in the sudoers file"), or `su`: root has no password.
8. **Fingerprint or security key.** No finger enrolled, or an unsupported reader; a key's
   `~/.config/Yubico/u2f_keys` copied without its SELinux label; with a key plugged in, sudo waits for a
   touch.
9. **The image's SELinux module missing.** Without `amethystora-pam`, every SSH code fails and the hours
   are not enforced. Tell: `semodule -l` lacks it.
10. **Domain accounts.** sssd down, the domain left, or a clock more than five minutes off, which
    Kerberos refuses (`ame security time` on a network that blocks its port 4460). Tell: `realm list`,
    `systemctl is-active sssd.service`, `timedatectl`.

## Fix
1. Wait ten minutes, or restart (the count lives in `/run`), or another administrator runs
   `sudo faillock --user NAME --reset` (root). `ame security lockout off` is the user's call alone: it
   gives up the limit on guessing passwords.
2. An administrator changes the hours in Parental Controls, or the account logs in at the desktop.
3. The account runs `ame security ssh-codes setup` at the machine; fix the clock (`timedatectl`).
   `ame security ssh-codes off` is the user's call.
4. On the client: `ssh -o IdentitiesOnly=yes -i KEY host`.
5. Once the user confirms the address is theirs, they run `ame security addresses ADDRESS` (root).
   `ame security failed-logins off` is theirs alone and gives up the blocking.
6. The user decides: `sudo systemctl enable --now sshd.service` (root), and beyond the tailnet
   `sudo firewall-cmd --add-service=ssh` (root), which opens SSH on every network joined.
7. An administrator makes the account one in Settings › System › Users; use `sudo`, never `su`.
8. `ame security fingerprint` or `ame security key` (the user's finger or key), or
   `restorecon -R ~/.config/Yubico`.
9. `sudo semodule -i /usr/share/selinux/packages/amethystora-pam.cil` (root): the image's own module.
10. `sudo systemctl restart sssd.service` (root); else the user runs `realm leave` and
    `realm join DOMAIN` (root). Never `authselect select`.

## Verify
- `sudo faillock --user NAME` (root) is empty; `ame security addresses` no longer lists the address.
- An `ssh` login from the client; `realm list` shows the domain and `id user@domain` answers.
- `state health` no longer points to this playbook.

## Undo
- `ame security lockout on`, `ame security failed-logins on`, `ame security ssh-codes on` (root).
- `sudo systemctl disable --now sshd.service`, `sudo firewall-cmd --remove-service=ssh` (root).
