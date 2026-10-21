#!/usr/bin/bash
# An update from an image that shipped /etc/audit/rules.d/60-amethystora.rules, as every image did until the
# audit rules became switches (2026-10-08), to one whose generator writes it at every boot: ostree's /etc merge
# takes the shipped file away where it was never edited and keeps an edited one, and either way the generator
# writes its own over it at the next boot, which loads. The older image is the running one with that file put
# back, committed from a checkout of hard links into the repository, as 89-soft-reboot.sh makes its updates;
# both are deployed unstaged, as 60-vanilla.sh does, since a staged deployment is lost at restart on the lab's
# disks. The machine is left with its deployments as they were.
source "$(dirname "$0")/lib.sh"

STATE=/var/lib/vmlab-tests/39-old-audit-rules
REPO=/sysroot/ostree/repo
RULES=etc/audit/rules.d/60-amethystora.rules
EDITED="## edited on this machine"
install -d -m 0700 "${STATE}"
systemctl stop uupd.timer 2>/dev/null

remember() { printf '%s\n' "$2" >"${STATE}/$1"; }
recall() { cat "${STATE}/$1" 2>/dev/null; }
rw() { unshare -m sh -c 'mount -o remount,rw /sysroot && "$@"' sh "$@"; }
# Not bootc status, which refuses to answer while a commit made here, without an image's manifest, is deployed
booted() { rpm-ostree status --json | jq -r '.deployments[] | select(.booted) | .checksum'; }
count() { rpm-ostree status --json | jq '.deployments | length'; }
# The default deployment's folder, the first that ostree admin status lists
newest() { ostree admin status | grep -oE '[[:alnum:]_-]+ [0-9a-f]{64}\.[0-9]+' | head -n 1 | sed 's|^\([^ ]*\) |/ostree/deploy/\1/deploy/|'; }
deploy() { timeout 1500 ostree admin deploy --origin-file="${STATE}/origin" "$1" 2>&1; }

case "${SUITE_PHASE}" in
    1)
        if [[ "$(count)" != 1 ]]; then
            skip "the machine has $(count) deployments, which this would change"
            finish
        fi
        remember original "$(booted)"
        cp "$(ostree admin --print-current-dir).origin" "${STATE}/origin"
        # The older image: the running one, with the rules file it shipped (the start of the last one shipped,
        # at bc7da77^), labelled as its neighbours are
        dir="${REPO}/tmp/vmlab-old-audit-rules"
        rw rm -rf "${dir}"
        if out="$({ rw ostree checkout --repo="${REPO}" -H "$(recall original)" "${dir}" &&
            rw sh -c "cat >'${dir}/usr/${RULES}' && chmod 0600 '${dir}/usr/${RULES}' &&
                chcon --reference='${dir}/usr/etc/audit/rules.d/99-amethystora-finalize.rules' '${dir}/usr/${RULES}'" <<'EOF' &&
## Amethystora audit rules: what an attacker has to touch to survive a reboot or to gain root.
## Keys used below: identity, privilege, persistence, hardening, modules, input-capture.

## Accounts, and who is allowed to become root
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k privilege
-w /etc/sudoers.d/ -p wa -k privilege

## Anything that starts itself, in the writable parts of the system
-w /etc/systemd/system/ -p wa -k persistence
-w /etc/xdg/autostart/ -p wa -k persistence
EOF
            rw ostree commit --repo="${REPO}" --parent="$(recall original)" -b vmlab/old-audit-rules -I --consume --bootable \
                --add-metadata-string=version=vmlab-old-audit-rules "${dir}" >/dev/null &&
            deploy vmlab/old-audit-rules; } 2>&1)"; then
            ok "an image that ships 60-amethystora.rules, made and deployed"
            reboot_and_continue
        else
            not_ok "could not make the older image" "$(tail -n 15 <<<"${out}")"
        fi
        ;;
    2)
        if [[ "$(booted)" == "$(recall original)" ]]; then
            not_ok "the machine did not start the older image"
            finish
        fi
        check "the older image runs, and ships the file" test -f "/usr/${RULES}"
        # Never edited: as the image shipped it. Its generator wrote over it at this boot; the older images'
        # wrote 61-amethystora-home.rules alone.
        cp -a "/usr/${RULES}" "/${RULES}"
        if out="$(deploy "$(recall original)")"; then
            next="$(newest)"
            [[ -d "${next}/etc" && ! -e "${next}/${RULES}" ]] && ok "never edited, the update's /etc merge takes it away" ||
                not_ok "the merge left it in ${next}" "$(head -n 3 "${next}/${RULES}" 2>&1)"
        else
            not_ok "could not deploy the machine's own image" "$(tail -n 15 <<<"${out}")"
        fi
        # Edited on this machine: the merge keeps it, and the next boot's generator writes its own over it
        echo "${EDITED}" >>"/${RULES}"
        if out="$(deploy "$(recall original)")"; then
            next="$(newest)"
            grep -qxF "${EDITED}" "${next}/${RULES}" 2>/dev/null && ok "edited, the merge keeps it" ||
                not_ok "the merge did not keep the edited file in ${next}" "$(ls -l "${next}/etc/audit/rules.d" 2>&1)"
            reboot_and_continue
        else
            not_ok "could not deploy the machine's own image" "$(tail -n 15 <<<"${out}")"
        fi
        ;;
    *)
        [[ "$(booted)" == "$(recall original)" ]] && ok "the machine's own image runs again" || not_ok "the machine runs $(booted)"
        if ! /usr/libexec/amethystora-security-config --is AUDIT_LOG on; then
            skip "the rules at boot: AUDIT_LOG is off on this machine"
        else
            { head -n 1 "/${RULES}" | grep -q '^## Generated by' && ! grep -qxF "${EDITED}" "/${RULES}"; } &&
                ok "the generator wrote its own over the edited file at boot" || not_ok "the edited file stayed" "$(head -n 3 "/${RULES}")"
            check "the generator ran at boot" systemctl is-active --quiet amethystora-audit-rules.service
            [[ "$(systemctl show -P Result audit-rules.service)" == success &&
                "$(systemctl show -P ExecMainStartTimestampMonotonic audit-rules.service)" != 0 ]] &&
                ok "the rules loaded at boot" || not_ok "the rules did not load" "$(journalctl -b -u audit-rules.service -o cat --no-pager | tail -n 8)"
            check "accounts are watched (an audit rule or the sensor)" sh -c 'auditctl -l | grep -q -- "-k identity\$" ||
                grep -qx "identity sensor" /run/amethystora/sensor/plan'
        fi
        # The older image and its commit go
        ostree admin undeploy 1 >/dev/null 2>&1
        rw ostree refs --repo="${REPO}" --delete vmlab/old-audit-rules >/dev/null 2>&1
        rw ostree prune --repo="${REPO}" --refs-only >/dev/null 2>&1
        [[ "$(count)" == 1 && -z "$(ostree refs --repo="${REPO}" vmlab/old-audit-rules 2>/dev/null)" ]] &&
            ok "the machine is left with its one deployment" || not_ok "the machine has $(count) deployments" "$(ostree admin status 2>&1)"
        rm -rf "${STATE}"
        ;;
esac
finish
