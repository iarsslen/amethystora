# shellcheck shell=bash

# Show "Welcome to Amethystora", the logo and system summary in new interactive terminals.
# `ame desktop greeting` turns it off. Skipped for root, and when a parent shell already greeted.
case "$-" in
*i*)
	if [ "$(id -u)" != "0" ] && [ -z "${AMETHYSTORA_GREETED-}" ] &&
		[ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/amethystora/no-greeting" ]; then
		AMETHYSTORA_GREETED=1
		export AMETHYSTORA_GREETED
		# The whole greeting in the first terminal of a session, and its welcome line in the ones after: the
		# system summary took longer than the rest of a new terminal. XDG_RUNTIME_DIR lasts until the last
		# session of the account ends.
		if [ -n "${XDG_RUNTIME_DIR-}" ] && [ -e "${XDG_RUNTIME_DIR}/amethystora-greeted" ]; then
			/usr/libexec/amethystora-greeting --short
		else
			[ -n "${XDG_RUNTIME_DIR-}" ] && : >"${XDG_RUNTIME_DIR}/amethystora-greeted" 2>/dev/null
			/usr/libexec/amethystora-greeting
		fi
	fi
	;;
esac
