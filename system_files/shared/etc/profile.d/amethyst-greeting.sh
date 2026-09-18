# shellcheck shell=bash

# Show "Welcome to Amethyst", the logo and system summary in new interactive terminals.
# `ujust toggle-user-motd` turns it off. Skipped for root, and when a parent shell already greeted.
case "$-" in
*i*)
	if [ "$(id -u)" != "0" ] && [ -z "${AMETHYST_GREETED-}" ] &&
		[ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/amethyst/no-greeting" ]; then
		AMETHYST_GREETED=1
		export AMETHYST_GREETED
		/usr/libexec/amethyst-greeting
	fi
	;;
esac
