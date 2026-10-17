function fish_greeting
    # Same greeting as /etc/profile.d/amethystora-greeting.sh; `ame desktop greeting` turns it off.
    set -l config_home $HOME/.config
    set -q XDG_CONFIG_HOME; and set config_home $XDG_CONFIG_HOME

    if test (id -u) = 0; or set -q AMETHYSTORA_GREETED; or test -e $config_home/amethystora/no-greeting
        return
    end
    set -gx AMETHYSTORA_GREETED 1

    # The whole greeting in the first terminal of a session, its welcome line in the ones after
    if set -q XDG_RUNTIME_DIR; and test -e $XDG_RUNTIME_DIR/amethystora-greeted
        /usr/libexec/amethystora-greeting --short
        return
    end
    set -q XDG_RUNTIME_DIR; and touch $XDG_RUNTIME_DIR/amethystora-greeted 2>/dev/null
    /usr/libexec/amethystora-greeting
end
