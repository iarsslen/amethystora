#!/usr/bin/bash
# The machine as it first boots: everything started, Secure Boot and lockdown on, the TPM there, the image's
# own kernel modules loading under Secure Boot (make-disk.sh enrolls its certificates, as an owner would),
# and nothing crashed.
source "$(dirname "$0")/lib.sh"

state="$(systemctl is-system-running --wait 2>/dev/null)"
if [[ "${state}" == running ]]; then
    ok "every unit started"
else
    failed="$(systemctl --failed --no-legend --plain | awk '{print $1}')"
    not_ok "the system is ${state}: $(paste -sd ' ' <<<"${failed}")" \
        "$(for unit in ${failed}; do journalctl -b -u "${unit}" -p warning --no-pager -o cat | tail -n 3; done)"
fi
check "Secure Boot is on" sh -c 'mokutil --sb-state | grep -q "SecureBoot enabled"'
check "the kernel is locked down" grep -qE '\[(integrity|confidentiality)\]' /sys/kernel/security/lockdown
check "a TPM 2.0 is there" test -c /dev/tpmrm0
check "the booted deployment is the image under test" sh -c 'rpm-ostree status --booted --json | jq -e ".deployments[0].\"container-image-reference\" | test(\"amethystora\")"'
check "the image's own kernel module loads under Secure Boot (v4l2loopback)" modprobe v4l2loopback
# The audit rules are written at boot by a unit whose sandbox, when systemd cannot set it up, skips it quietly
check "the audit rules were written at boot" systemctl is-active --quiet amethystora-audit-rules.service
check "the image's audit rules are loaded" sh -c 'auditctl -l | grep -q -- "-k identity\$"'
dumps="$(coredumpctl list --no-legend --no-pager 2>/dev/null)"
if [[ -z "${dumps}" ]]; then ok "nothing crashed"; else not_ok "something crashed" "${dumps}"; fi
finish
