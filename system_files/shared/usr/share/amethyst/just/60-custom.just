# vim: set ft=make :

# Toggle the logo and system summary shown in new terminals
toggle-user-motd:
    #!/usr/bin/bash
    FLAG="${XDG_CONFIG_HOME:-$HOME/.config}/amethyst/no-greeting"
    if [ -e "${FLAG}" ]; then
        rm -f "${FLAG}"
        echo "Terminal greeting enabled"
    else
        mkdir -p "$(dirname "${FLAG}")"
        touch "${FLAG}"
        echo "Terminal greeting disabled"
    fi
