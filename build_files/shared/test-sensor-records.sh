#!/usr/bin/bash
# The sensor's record writer against ausearch: feed it JSON events (no BPF) and check that ausearch reads
# the records it writes as the sentences the security watcher expects, exactly as it reads what auditd logs
# (plans/security/PLAN-audit-cost.md section 4.4). This is the parity gate that needs no kernel: the live
# BPF side is checked in the VM lab (tests/vm/suites).
#
# Runs in 20-tests.sh on the base image, which has ausearch. AMETHYSTORA_SENSOR overrides the binary for the
# dev container.

set -uo pipefail

SENSOR="${AMETHYSTORA_SENSOR:-/usr/libexec/amethystora-sensor}"
fail=0
note() { echo "test-sensor-records: $*" >&2; fail=1; }

command -v ausearch >/dev/null || { echo "test-sensor-records: ausearch not found, skipping" >&2; exit 0; }
[[ -x "${SENSOR}" ]] || { echo "test-sensor-records: ${SENSOR} not found" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
log="${work}/audit.log"

# One line an event. comm is set where ausearch reads it rather than the exe (a char-device open, a failed
# open), so the sentence is stable.
"${SENSOR}" --records >"${log}" <<'EVENTS'
{"op":1,"syscall":257,"result":3,"keys":["privilege"],"flags":2147483648,"dir":"/etc/sudoers.d","name":"x","parent_mode":"040750","mode":"0100644","exe":"/usr/bin/tee"}
{"op":2,"syscall":263,"result":0,"keys":["privilege"],"dir":"/etc/sudoers.d","name":"x","parent_mode":"040750","mode":"0100644","exe":"/usr/bin/rm"}
{"op":4,"syscall":258,"result":0,"keys":["persistence"],"dir":"/etc/systemd/system","name":"x.d","parent_mode":"040755","mode":"040755","exe":"/usr/bin/mkdir"}
{"op":9,"syscall":268,"result":0,"keys":["hardening"],"dir":"/etc/pam.d","name":"su","mode":"0100644","args":["ffffff9c","55d1","1ed","0"],"exe":"/usr/bin/chmod"}
{"op":8,"syscall":316,"result":0,"keys":["identity"],"dir":"/etc","name":"passwd-","dir2":"/etc","name2":"passwd","parent_mode":"040755","mode":"0100644","exe":"/usr/sbin/useradd"}
{"op":15,"syscall":313,"result":0,"keys":["modules"],"module":"v4l2loopback","args":["3","55d1","0","0"],"exe":"/usr/bin/kmod"}
{"op":16,"syscall":176,"result":0,"keys":["modules"],"module":"v4l2loopback","args":["55d1","800","0","0"],"exe":"/usr/bin/kmod"}
{"op":1,"syscall":257,"result":3,"keys":["credentials"],"flags":134217728,"dir":"/var/home/alice/.ssh","name":"id_rsa","cwd":"/var/home/alice","mode":"0100600","exe":"/usr/bin/cat"}
{"op":1,"syscall":257,"result":3,"keys":["hardening"],"dir":"/etc","name":"a file","mode":"0100644","exe":"/usr/bin/vi"}
EVENTS

[[ -s "${log}" ]] || note "the record writer produced nothing"

text="$(LC_ALL=C ausearch -if "${log}" --format text </dev/null 2>/dev/null)"

# The sentences the watcher's read_audit matches on: verb, object and the program, as auditd would give them.
expect() { grep -qF -- "$1" <<<"${text}" || note "missing from the sentences: $1"; }
expect "opened-file /etc/sudoers.d/x using /usr/bin/tee"
expect "deleted /etc/sudoers.d/x using /usr/bin/rm"
expect "created-directory /etc/systemd/system/x.d using /usr/bin/mkdir"
expect "changed-file-permissions-of /etc/pam.d/su to 0755 using /usr/bin/chmod"
expect "renamed /etc/passwd- to /etc/passwd using /usr/sbin/useradd"
expect "loaded-kernel-module v4l2loopback using /usr/bin/kmod"
expect "opened-file /var/home/alice/.ssh/id_rsa using /usr/bin/cat"
# A name with a space is hex-encoded by the writer and read back whole, the last event, which needs its EOE.
expect "opened-file /etc/a file using /usr/bin/vi"

# The raw read the watcher uses for exec and credentials: PATH item 0 joined with CWD, and the program.
raw="$(LC_ALL=C ausearch -if "${log}" -m SYSCALL,CWD,PATH -k credentials -i </dev/null 2>/dev/null)"
grep -qF -- "/var/home/alice/.ssh/id_rsa" <<<"${raw}" || note "the credentials raw record lost its path"

[[ "${fail}" -eq 0 ]] && echo "test-sensor-records: ok"
exit "${fail}"
