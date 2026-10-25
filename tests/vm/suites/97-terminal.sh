#!/usr/bin/bash
# kitty as the terminal, and the prompt in it. xdg-terminal-exec (Super+Return, amethystora-in-terminal) opens kitty,
# which starts and stays open; the image's kitty.conf loads and includes the theme's colours; switching the theme
# rewrites them and a window that is open reads them again and stays open (SIGUSR1); and the prompt is the powerline
# one, drawn from the same palette: user@host, the folder and, in a git repository, its branch, each followed by
# Nerd Fonts' arrow, then the command on a line of its own.
source "$(dirname "$0")/lib.sh"

HOME_DIR="/var/home/${TEST_USER}"
THEME_DIR="${HOME_DIR}/.config/amethystora/current/theme"
ARROW=$''  # U+E0B0, as UTF-8 bytes whatever the locale

if ! wait_for 300 has_session; then
    skip "no session for ${TEST_USER} (10-account.sh)"
    finish
fi

kitty_running() { pgrep -u "${TEST_USER}" -x kitty >/dev/null; }
colour() { sed -n "s/^$2 = \"\(#[0-9a-fA-F]*\)\".*/\1/p" "/usr/share/amethystora/themes/$1/colors.toml"; }
theme_key() { sed -n "s/^$1 \(#[0-9a-fA-F]*\).*/\1/p" "${THEME_DIR}/kitty-theme.conf"; }
# The prompt as starship draws it for the account, in a folder, with the colours left in
prompt_in() { in_session "cd '$1' && STARSHIP_SHELL=bash starship prompt --status 0"; }

# --- The terminal xdg-terminal-exec opens -----------------------------------------------------------------------
check "kitty is installed" rpm -q kitty
check "the Terminal launchers of the image name kitty first" \
    test "$(grep -hv '^#' /etc/xdg/xdg-terminals.list /etc/xdg/gnome-xdg-terminals.list | sort -u | head -n1)" == "kitty.desktop"

user_bus pkill -x kitty 2>/dev/null
in_session "xdg-terminal-exec sleep 120" >/dev/null 2>&1 &
if wait_for 60 kitty_running; then
    ok "xdg-terminal-exec opens kitty"
else
    not_ok "xdg-terminal-exec did not open kitty" \
        "$(user_bus journalctl --user -b --since -2min --no-pager -o cat 2>/dev/null | tail -n 12)"
fi
sleep 8
kitty_running && ok "kitty is still open eight seconds later" ||
    not_ok "kitty closed by itself" "$(user_bus journalctl --user -b --since -2min --no-pager -o cat 2>/dev/null | grep -i kitty | tail -n 8)"

# --- The configuration and the theme in it ----------------------------------------------------------------------
settings="$(in_session "kitty +runpy 'from kitty.cli import create_default_opts; o = create_default_opts(); print(o.font_size, o.tab_bar_style, o.update_check_interval, o.allow_remote_control)'" 2>&1)"
[[ "${settings}" == "11.0 powerline 0.0 "* ]] && ok "the image's kitty.conf is what kitty reads (${settings})" ||
    not_ok "kitty does not read the image's kitty.conf" "${settings}"

original="$(runuser -u "${TEST_USER}" -- amethystora-theme current 2>/dev/null || echo amethystora)"
for theme in nord amethystora-light; do
    out="$(in_session "AMETHYSTORA_THEME_QUIET=1 AMETHYSTORA_THEME_SKIP_BACKGROUND=1 amethystora-theme set ${theme}" 2>&1)" ||
        not_ok "${theme} did not apply" "${out}"
    check "${theme}: kitty's background is the theme's" test "$(theme_key background)" == "$(colour "${theme}" background)"
    check "${theme}: kitty's accent tab is the theme's" test "$(theme_key active_tab_background)" == "$(colour "${theme}" accent)"
    check "${theme}: kitty's palette is the theme's" test "$(theme_key color4)" == "$(colour "${theme}" color4)"
    sleep 2
    kitty_running && ok "${theme}: the open kitty took the colours and stayed open" ||
        not_ok "${theme}: the open kitty closed when the theme was switched"
    rendered="$(in_session "KT='${THEME_DIR}/kitty-theme.conf' kitty +runpy 'import os; from kitty.config import load_config; b = []; load_config(os.environ[\"KT\"], accumulate_bad_lines=b); print(len(b))'" 2>&1)"
    [[ "${rendered}" == 0 ]] && ok "${theme}: kitty accepts every line of its theme" || not_ok "${theme}: kitty rejects lines of its theme" "${rendered}"
done

# --- The prompt --------------------------------------------------------------------------------------------------
check "the prompt is the theme's: ~/.config/starship.toml leads into the account's theme" \
    test "$(readlink "${HOME_DIR}/.config/starship.toml")" == "${THEME_DIR}/starship.toml"
repo="${HOME_DIR}/vmlab-terminal/rasa"
runuser -u "${TEST_USER}" -- sh -c "mkdir -p '${repo}/sub' && cd '${repo}' && git init -q -b master . && \
    git -c user.name=vmlab -c user.email=vmlab@example.org commit -q --allow-empty -m first && echo x >new"
inside="$(prompt_in "${repo}/sub")"
outside="$(prompt_in "${HOME_DIR}")"
plain() { sed 's/\x1b\[[0-9;]*m//g; s/\\\[//g; s/\\\]//g' <<<"$1"; }
inside_plain="$(plain "${inside}")"
outside_plain="$(plain "${outside}")"
echo "# in a repository: ${inside_plain}"
echo "# outside one:     ${outside_plain}"
[[ "${inside_plain}" == *"${TEST_USER}"* && "${inside_plain}" == *rasa/sub* && "${inside_plain}" == *master* ]] &&
    ok "in a repository the prompt names the account, the folder and the branch" ||
    not_ok "the prompt in a repository is missing a part" "${inside_plain}"
[[ "$(grep -o "${ARROW}" <<<"${inside_plain}" | wc -l)" == 3 ]] &&
    ok "in a repository every segment is followed by an arrow (account, folder, branch)" ||
    not_ok "in a repository the arrows are not three" "${inside_plain}"
[[ "$(grep -o "${ARROW}" <<<"${outside_plain}" | wc -l)" == 2 && "${outside_plain}" != *master* ]] &&
    ok "outside a repository there is no branch segment, and the folder's arrow closes the line" ||
    not_ok "outside a repository the prompt is not account and folder" "${outside_plain}"
[[ "${inside}" == *"48;2;"* && "${inside}" == *"38;2;"* ]] && ok "the segments are drawn in the theme's true colours" ||
    not_ok "the prompt has no true colours" "${inside}"
[[ "$(tail -n 1 <<<"${inside_plain}")" == *"▶"* || "${inside_plain}" == *"▶"* ]] && ok "the command goes on a line of its own, after ▶" ||
    not_ok "no ▶ line for the command" "${inside_plain}"

# --- Back as it was -----------------------------------------------------------------------------------------------
in_session "AMETHYSTORA_THEME_QUIET=1 AMETHYSTORA_THEME_SKIP_BACKGROUND=1 amethystora-theme set ${original}" >/dev/null 2>&1
user_bus pkill -x kitty 2>/dev/null
rm -rf "${HOME_DIR}/vmlab-terminal"
finish
