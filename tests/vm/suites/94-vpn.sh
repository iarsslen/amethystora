#!/usr/bin/bash
# The VPNs people are given at work (NetworkManager's fortisslvpn, l2tp, libreswan and sstp plugins beside the
# image's openconnect, openvpn and vpnc): each plugin accepts a connection, an OpenVPN file imports, L2TP's two
# kernel modules load the way its daemon gets them (by alias, which Fedora's blacklist would stop) while l2tp_eth
# stays blocked, strict kernel mode is the one thing that takes IPsec away, and libreswan starts and stops
# without a denial. No server is run here; connecting to one is not tested.
source "$(dirname "$0")/lib.sh"

SINCE="$(date '+%F %T')"
CONNECTIONS=(vmlab-vpn-fortisslvpn vmlab-vpn-l2tp vmlab-vpn-libreswan vmlab-vpn-sstp vmlab-vpn-openconnect
    vmlab-vpn-openvpn vmlab-vpn-vpnc vmlab-vpn-imported)
OVPN_DIR="$(mktemp -d)"
OVPN="${OVPN_DIR}/vmlab.ovpn"
touch "${OVPN_DIR}/ca.pem"
cleanup() {
    for connection in "${CONNECTIONS[@]}"; do nmcli connection delete "${connection}" >/dev/null 2>&1 || true; done
    systemctl stop ipsec.service >/dev/null 2>&1 || true
    rm -rf "${OVPN_DIR}"
}
trap cleanup EXIT
cleanup

# A connection for each plugin: nmcli finds the plugin through its .name file and keeps the connection
declare -A DATA=(
    [fortisslvpn]="gateway = vpn.example.org, user = tester"
    [l2tp]="gateway = 192.0.2.1, user = tester, ipsec-enabled = no"
    [libreswan]="right = 192.0.2.1, leftid = tester, ikev2 = insist"
    [sstp]="gateway = vpn.example.org, user = tester"
    [openconnect]="gateway = vpn.example.org, protocol = anyconnect"
    [openvpn]="remote = 192.0.2.1, connection-type = password, username = tester"
    [vpnc]="IPSec gateway = 192.0.2.1, IPSec ID = vmlab, Xauth username = tester"
)
for plugin in fortisslvpn l2tp libreswan sstp openconnect openvpn vpnc; do
    if out="$(nmcli connection add type vpn vpn-type "${plugin}" con-name "vmlab-vpn-${plugin}" ifname -- \
        vpn.data "${DATA[${plugin}]}" 2>&1)" &&
        [[ "$(nmcli -g vpn.service-type connection show "vmlab-vpn-${plugin}")" == "org.freedesktop.NetworkManager.${plugin}" ]]; then
        ok "NetworkManager keeps a ${plugin} VPN"
    else
        not_ok "NetworkManager did not keep a ${plugin} VPN" "${out}"
    fi
done

cat >"${OVPN}" <<'OVPN'
client
dev tun
proto udp
remote 192.0.2.1 1194
resolv-retry infinite
nobind
ca ca.pem
OVPN
if out="$(nmcli connection import type openvpn file "${OVPN}" 2>&1)"; then
    imported="$(sed -n "s/^Connection '\(.*\)' (.*) successfully added\.$/\1/p" <<<"${out}")"
    [[ -n "${imported}" ]] && nmcli connection modify "${imported}" connection.id vmlab-vpn-imported
    ok "an .ovpn file imports"
else
    not_ok "an .ovpn file did not import" "${out}"
fi

# L2TP's modules, by the aliases the daemon asks for (the generic netlink family and the PPP pseudowire type);
# `modprobe l2tp_ppp` by name would pass with the blacklist in place
for module in l2tp_ppp l2tp_netlink; do modprobe -r "${module}" >/dev/null 2>&1 || true; done
if out="$(modprobe net-pf-16-proto-16-family-l2tp 2>&1 && modprobe net-l2tp-type-7 2>&1)" &&
    lsmod | grep -q '^l2tp_netlink ' && lsmod | grep -q '^l2tp_ppp '; then
    ok "l2tp_netlink and l2tp_ppp load by alias"
else
    not_ok "l2tp_netlink and l2tp_ppp did not load by alias" "${out:-}" "$(lsmod | grep l2tp)"
fi
# l2tp_eth is Fedora's to keep blacklisted: its alias loads nothing
modprobe -r l2tp_eth >/dev/null 2>&1 || true
modprobe net-l2tp-type-5 >/dev/null 2>&1 || true
if lsmod | grep -q '^l2tp_eth '; then not_ok "l2tp_eth loaded by alias, Fedora's blacklist was meant to stop it"; else ok "l2tp_eth stays blacklisted"; fi

# IPsec's modules are not blocked as the image ships (ame security kernel strict blocks them)
if modprobe -n -v esp4 2>&1 | grep -q '/usr/bin/false'; then
    skip "esp4 is blocked: ame security kernel strict is on, and IPsec VPNs do not work"
else
    ok "IPsec's modules load"
fi

# Libreswan starts when a connection needs it and not before, and stops again
if [[ "$(systemctl is-enabled ipsec.service 2>/dev/null || true)" != enabled ]] && ! systemctl is-active --quiet ipsec.service; then
    ok "ipsec.service is neither enabled nor running while no IPsec VPN is up"
else
    not_ok "ipsec.service runs or is enabled with no IPsec VPN" "$(systemctl is-enabled ipsec.service 2>&1)"
fi
if out="$(systemctl start ipsec.service 2>&1)" && wait_for 30 systemctl is-active --quiet ipsec.service; then
    ok "libreswan starts"
    check "libreswan answers" ipsec whack --status
else
    not_ok "libreswan did not start" "${out}" "$(journalctl -u ipsec.service -b --no-pager -o cat | tail -n 15)"
fi
systemctl stop ipsec.service >/dev/null 2>&1 || true

# SELinux has said nothing about these programs
denials="$(ausearch -m avc,user_avc -ts "${SINCE}" 2>/dev/null | grep -E 'comm="(pluto|ipsec|nm-[a-z0-9]*-service|kl2tpd|pppd|sstpc|openfortivpn)"' || true)"
if [[ -z "${denials}" ]]; then ok "SELinux denied none of the VPN programs"; else not_ok "SELinux denied a VPN program" "${denials}"; fi

finish
