#!/usr/bin/bash
# The Measuring section of plans/security/PLAN-threat-detection.md, as far as one VM run can take it: with the
# thorough profile on, a representative ATT&CK technique for each detection feature that runs on the base
# image, and the 2025-2026 supply-chain cases the plan names, are reproduced with benign stand-ins (marker
# files, a copy of /usr/bin/true, reading bait credential files this suite planted) and the watcher is asked
# what it caught. Each check prints a "# COVERAGE Tnnnn key level" line, which the run's summary keeps, so the
# coverage table is rebuilt every run rather than written down once. Nothing here runs real malware, reaches
# the network, or weakens a check: a benign read of a planted ~/.aws/credentials trips the same audit rule a
# stealer would.
#
# Features that need a kernel the lab cannot give benignly (SELinux denials, BPF programs) are skipped with
# their reason; the full Atomic Red Team sweep and the week of `record` on real machines stay the maintainer's,
# as the plan says.
source "$(dirname "$0")/lib.sh"

HOME_DIR="/var/home/${TEST_USER}"
HISTORY=/var/log/amethystora-security-events.jsonl
config=/usr/libexec/amethystora-security-config
snapshot=/usr/libexec/amethystora-home-snapshot

if ! wait_for 300 has_session; then
    skip "no session for ${TEST_USER} (10-account.sh)"
    finish
fi

# Phase 1: plant the bait that an audit rule is written for only if the file is there at boot (the fake AI
# agent AGENT_CLIS watches, the credential files CREDENTIALS watches), turn the thorough profile on, and
# restart so the kernel loads the rules. The triggers themselves wait for phase 2.
if [[ "${SUITE_PHASE}" == 1 ]]; then
    check "the thorough profile goes on" "${config}" profile thorough
    as_user "set -e
        mkdir -p ~/.local/bin ~/.aws ~/.local/lib/python3.13/site-packages ~/.claude
        # A harmless stand-in for an installed AI agent: it is only ever run, never read for its contents
        printf '#!/usr/bin/bash\nexit 0\n' >~/.local/bin/claude && chmod 0755 ~/.local/bin/claude
        # Bait secrets a stealer sweeps (the Nx/Shai-Hulud indicator), with no real secret in them
        printf 'registry=https://example.invalid\n//example.invalid/:_authToken=ATOMIC-REDACTED\n' >~/.npmrc
        printf '[default]\naws_access_key_id=ATOMIC-REDACTED\naws_secret_access_key=ATOMIC-REDACTED\n' >~/.aws/credentials"
    reboot_and_continue
fi

# --- Phase 2 ---------------------------------------------------------------------------------------------
[[ "$(${config} --profile)" == thorough ]] && ok "the profile is still thorough after the restart" ||
    not_ok "the profile is $(${config} --profile) after the restart"

# Where the history stands at the start of phase 2: the chains check looks across all of phase 2, since a
# chain forms as soon as two of this account's tactics are in the half-hour window, which may be an earlier
# watcher run than the one that adds the step we last triggered.
HISTORY_AT_START="$(wc -l <"${HISTORY}" 2>/dev/null || echo 0)"

# 30-detection already made tester a "Credential Access, Execution" chain earlier in this boot session, and
# the watcher correctly says each chain once: its entry in chains-said would dedup the identical two-tactic
# chain this suite builds, so a chain only showed here when tester happened to pick up a third tactic -- which
# was intermittent. Clear the watcher's chain state so this suite measures chain formation from its own steps,
# the way the watcher would on a machine where this attack is the first. The audit rules and findings are
# untouched; only the chain window and the said-once record are reset.
rm -f /var/lib/amethystora/security/chain-window /var/lib/amethystora/security/chains-said

# A technique is measured by running its benign trigger in the test account's own session, then one run of
# the watcher, then looking at what it added to the history since. coverage records the mapping either way.
run_watcher() { systemctl start amethystora-security-watch.service; }
BEFORE=0

mark() { BEFORE="$(wc -l <"${HISTORY}" 2>/dev/null || echo 0)"; }
# since: the findings this run added, as compact JSON lines
since() { tail -n +"$((BEFORE + 1))" "${HISTORY}" 2>/dev/null; }
# caught TECHNIQUE KEY FILTER WHAT: ok when a finding matching FILTER (a jq boolean over one finding) is
# there, and prints the coverage line with the level it came in at; not ok with what was found otherwise.
caught() {
    local technique="$1" key="$2" filter="$3" what="$4" found level
    found="$(since)"
    level="$(jq -r -s "[.[] | select(${filter})] | if length == 0 then \"\" elif any(.level == \"critical\") then \"critical\" else (.[0].level // \"normal\") end" <<<"${found}" 2>/dev/null)"
    if [[ -n "${level}" ]]; then
        echo "# COVERAGE ${technique} ${key} ${level}"
        ok "${what} (${technique} -> ${key}, ${level})"
    else
        echo "# COVERAGE ${technique} ${key} MISSED"
        not_ok "${what} not caught (${technique} -> ${key})" "$(jq -r -s '.[] | "\(.key) \(.level): \(.text)"' <<<"${found}" | tail -n 20)"
    fi
}

# T1059 Command execution from a world-writable folder: a program run from /tmp (PROCESSES). read_processes
# scans /proc for running programs, so the stand-in has to be alive while the watcher looks: a copy of
# /usr/bin/sleep, started as a non-waiting transient unit, is still running when the watcher scans, then stopped.
mark
in_session "cp /usr/bin/sleep /tmp/art-dropped-payload"
user_bus systemd-run --user --unit=art-proc --collect --quiet -- /tmp/art-dropped-payload 60 || true
wait_for 15 pgrep -u "${TEST_USER}" -f /tmp/art-dropped-payload
run_watcher
caught T1059 processes '.key == "processes" and (.text | contains("art-dropped-payload"))' "a program run from /tmp"
user_bus systemctl --user stop art-proc >/dev/null 2>&1 || true

# T1547.013 / T1543.002 Persistence: an XDG autostart entry and a user systemd unit, which the audit rules on
# those folders record (PERSISTENCE, on by default). Benign: both only touch a marker.
mark
as_user "mkdir -p ~/.config/autostart ~/.config/systemd/user
    printf '[Desktop Entry]\nType=Application\nName=art\nExec=/bin/true\n' >~/.config/autostart/art-persist.desktop
    printf '[Unit]\nDescription=art\n[Service]\nExecStart=/bin/true\n[Install]\nWantedBy=default.target\n' >~/.config/systemd/user/art-persist.service"
# A later write to the same watched file, so ausearch releases the two above (it holds an event until a newer
# one is more than two seconds past it); the same file folds into the same finding, nothing new
sleep 3
as_user "printf '[Desktop Entry]\nType=Application\nName=art\nExec=/bin/true\n' >~/.config/autostart/art-persist.desktop"
sleep 1
run_watcher
caught T1547.013 persistence '.key == "persistence" and (.text | contains("art-persist"))' "an autostart entry and a user service added"

# The Nx / Shai-Hulud case (T1059 + T1552.001): a package install script runs an AI agent with its checks off
# and sweeps the account's secrets. Reproduced benignly: a non-terminal session runs the planted fake agent
# with a bypass flag, then reads the bait ~/.npmrc and ~/.aws/credentials in one process (which is critical:
# one process, two kinds of secret). cat is not an allowed reader of those, so it is flagged, where node
# reading its own ~/.npmrc would not be.
mark
in_session "~/.local/bin/claude --dangerously-skip-permissions >/dev/null 2>&1 || true
    cat ~/.npmrc ~/.aws/credentials >/dev/null"
sleep 4
in_session "cat ~/.npmrc >/dev/null"   # a newer event, so ausearch releases the ones above
sleep 3
run_watcher
caught T1059.nx agent-clis '.key == "agent-clis" and (.text | contains("--dangerously-skip-permissions"))' "an AI agent run with its checks off, no terminal"
caught T1552.001 credentials '.key == "credentials" and .level == "critical"' "one process reading two kinds of secret"
# T1059 + T1552 (and the earlier steps) joined into a chain for the account (CHAINS). A chain is said once as
# soon as two tactics are in the window and again when it grows, so it may land in an earlier run than this
# one: look across all of phase 2, not just since the last mark. On a miss, dump the watcher's chain state so
# the next run says whether the window held the tactics (a watcher problem) or not (the suite's triggers).
phase2() { tail -n +"$((HISTORY_AT_START + 1))" "${HISTORY}" 2>/dev/null; }
# The chain state, printed every run (pass or fail) as "# " lines run.mjs keeps in full, so the intermittent
# miss can be characterised either way: what read_chains' own jq would emit now from the live window, what it
# has already said, and what reached the history. If the jq emits a tester chain but none is in the history,
# the watcher computed it and dropped it (dedup or a bug, image side); if the jq emits nothing, the window did
# not hold two of tester's tactics (the suite's triggers).
win=/var/lib/amethystora/security/chain-window
said=/var/lib/amethystora/security/chains-said
emits="$(jq -rs '
    [.[] | select(.account == "-" and .tactic == "Command and Control")] as $c2
    | [.[] | select(.account != "-")] | group_by(.account)[]
    | . as $own
    | ($own | map(.tactic) | any(. == "Execution" or . == "Credential Access")) as $active
    | ($own + (if $active then $c2 else [] end)) as $all
    | ($all | map(.tactic) | unique) as $tactics
    | select(($tactics | length) >= 2)
    | [$own[0].account, ($tactics | join("+"))] | join(" ")' "${win}" 2>&1 | paste -sd';')"
echo "# chains-debug window-lines=$(wc -l <"${win}" 2>/dev/null) tester-tactics=$(jq -r 'select(.account == "'"${TEST_USER}"'") | .tactic' "${win}" 2>/dev/null | sort -u | paste -sd+)"
echo "# chains-debug jq-emits-now=[${emits}]"
echo "# chains-debug chains-said=[$(sed 's/\x1f/|/g' "${said}" 2>/dev/null | paste -sd';')]"
echo "# chains-debug phase2-chains=[$(phase2 | jq -r -s '.[] | select(.key == "chains") | "\(.account):\(.level)"' 2>/dev/null | paste -sd';')]"
chain_level="$(phase2 | jq -r -s '[.[] | select(.key == "chains" and .account == "'"${TEST_USER}"'")]
    | if length == 0 then "" elif any(.level == "critical") then "critical" else (.[0].level // "normal") end' 2>/dev/null)"
if [[ -n "${chain_level}" ]]; then
    echo "# COVERAGE chains chains ${chain_level}"
    ok "the steps joined into a chain (chains -> chains, ${chain_level})"
else
    echo "# COVERAGE chains chains MISSED"
    not_ok "the steps joined into a chain not caught (chains -> chains); see the # chains-debug lines"
fi

# The LiteLLM case (T1546): a Python .pth file runs an import at every Python start, read by the account's own
# reader (DEV_HOOKS). Benign: the import is of a module that does nothing.
mark
as_user "printf 'import sys  # art-litellm stand-in\n' >~/.local/lib/python3.13/site-packages/art_hook.pth"
sleep 2
run_watcher
caught T1546.litellm dev-hooks '.key == "dev-hooks" and (.text | contains(".pth"))' "a Python .pth startup hook"

# The ChainDrop case: a hook planted in an AI agent's own settings, which it runs by itself (AGENT_CONFIG),
# read by the account's reader. Benign: the hook command only touches a marker.
mark
as_user 'printf "{\"hooks\":{\"PreToolUse\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"/bin/touch /tmp/art-chaindrop\"}]}]}}\n" >~/.claude/settings.json'
sleep 2
run_watcher
caught T1546.chaindrop agent-config '.key == "agent-config" and (.account == "'"${TEST_USER}"'")' "a hook planted in an agent's settings"

# T1486 Data encrypted for impact (feature 3): a mass rewrite of an account's files from readable to random
# between two hourly snapshots. Needs /var/home to be its own btrfs subvolume, which an installer-made disk
# has; where it is not, this is skipped rather than failed.
# read_snapshots only records a baseline on its first run, so the readable files and a watcher run come first,
# then the encrypting rewrite and a second snapshot: the run after that is the one that compares them.
if [[ "$(stat -f -c %T /var/home 2>/dev/null)" == btrfs && "$(stat -c %i /var/home 2>/dev/null)" == 256 ]] &&
    "${snapshot}" >/dev/null 2>&1; then
    as_user "mkdir -p ~/art-ransom && for i in \$(seq 1 400); do yes 'the quick brown fox jumps over the lazy dog ' | head -c 4096 >~/art-ransom/file\$i.txt; done"
    "${snapshot}" >/dev/null 2>&1   # the snapshot the rewrite is measured against
    run_watcher                      # baseline: records that snapshot, says nothing
    as_user "for i in \$(seq 1 400); do head -c 4096 /dev/urandom >~/art-ransom/file\$i.txt; done"
    "${snapshot}" >/dev/null 2>&1   # the snapshot after the rewrite
    mark
    run_watcher
    caught T1486 snapshot-watch '.key == "snapshot-watch" and .level == "critical" and (.text | contains("ransomware"))' "a mass encrypting rewrite between snapshots"
else
    echo "# COVERAGE T1486 snapshot-watch SKIP /var/home is not its own btrfs subvolume here"
    skip "T1486 snapshot-watch: /var/home is not a btrfs subvolume of its own in this disk layout"
fi

# What the lab cannot trip benignly, left to the maintainer's Atomic Red Team sweep:
echo "# COVERAGE T1562.001 selinux-denials MANUAL needs a confined service to step outside its policy"
echo "# COVERAGE T1014 bpf-programs MANUAL needs bpftool to load a program (base image ships none)"
skip "T1562.001 (SELinux denials) and T1014 (BPF programs): measured by hand, no benign reliable trigger here"

# What runs where the watcher cannot see a time cost otherwise: the watcher's own last-run timings, which the
# Settings page reads from status.json, so a run of this suite also prints what the thorough profile costs.
timings="$(jq -r '.timings // {} | to_entries | sort_by(-.value)[] | "\(.key)=\(.value)ms"' /var/lib/amethystora/security/status.json 2>/dev/null | head -n 12 | paste -sd ' ')"
[[ -n "${timings}" ]] && echo "# TIMINGS ${timings}"

finish
