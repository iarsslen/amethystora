function fish_greeting
    # Same greeting as /etc/profile.d/amethyst-greeting.sh; `ujust toggle-user-motd` turns it off.
    set -l config_home $HOME/.config
    set -q XDG_CONFIG_HOME; and set config_home $XDG_CONFIG_HOME

    if test (id -u) = 0; or set -q AMETHYST_GREETED; or test -e $config_home/amethyst/no-greeting
        return
    end
    set -gx AMETHYST_GREETED 1

    /usr/libexec/amethyst-greeting
end
