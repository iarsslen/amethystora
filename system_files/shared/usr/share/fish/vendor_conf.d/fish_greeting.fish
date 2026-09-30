function fish_greeting
    # Same greeting as /etc/profile.d/amethystora-greeting.sh; `ujust toggle-user-motd` turns it off.
    set -l config_home $HOME/.config
    set -q XDG_CONFIG_HOME; and set config_home $XDG_CONFIG_HOME

    if test (id -u) = 0; or set -q AMETHYSTORA_GREETED; or test -e $config_home/amethystora/no-greeting
        return
    end
    set -gx AMETHYSTORA_GREETED 1

    /usr/libexec/amethystora-greeting
end
