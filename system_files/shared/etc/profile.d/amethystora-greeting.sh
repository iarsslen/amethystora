# shellcheck shell=bash

# Show "Welcome to Amethystora", the logo and system summary in new interactive terminals.
# `ame desktop greeting` turns it off. Skipped for root, and when a parent shell already greeted.
case "$-" in
*i*)
	if [ "$(id -u)" != "0" ] && [ -z "${AMETHYSTORA_GREETED-}" ] &&
		[ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/amethystora/no-greeting" ]; then
		AMETHYSTORA_GREETED=1
		export AMETHYSTORA_GREETED
		/usr/libexec/amethystora-greeting
	fi
	;;
esac
