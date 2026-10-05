# Completion for amethystora-pkg (/usr/bin/amethystora-pkg); amepkg.fish hands its short name to this.
# Names are read from the folders the command keeps them in: listing containers asks podman, which is
# too slow to wait for at every Tab.

function __amethystora_pkg_names
    set -l data (set -q XDG_DATA_HOME; and echo $XDG_DATA_HOME; or echo $HOME/.local/share)
    set -l config (set -q XDG_CONFIG_HOME; and echo $XDG_CONFIG_HOME; or echo $HOME/.config)
    set -l dirs /usr/share/amethystora/pkg/$argv[1] $data/amethystora/pkg/$argv[1]
    test -e $config/amethystora/aur; and set -a dirs /usr/share/amethystora/pkg/aur/$argv[1]
    for file in $dirs/*.json
        basename $file .json
    end
end

function __amethystora_pkg_containers
    set -l state (set -q XDG_STATE_HOME; and echo $XDG_STATE_HOME; or echo $HOME/.local/state)
    for file in $state/amethystora/pkg/containers/*.json
        basename $file .json
    end
end

# Whether the first word after the command is the one given. A predicate rather than `test (...) = x`,
# which fails with an error before there is a first word.
function __amethystora_pkg_first
    set -l words (commandline -opc)
    test (count $words) -ge 2; and test "$words[2]" = "$argv[1]"
end

# Right after the name of one of the containers
function __amethystora_pkg_in_container
    set -l words (commandline -opc)
    test (count $words) -eq 2; or return 1
    contains -- $words[2] (__amethystora_pkg_containers)
end

function __amethystora_pkg_container_doing
    set -l words (commandline -opc)
    test (count $words) -ge 3; or return 1
    contains -- $words[2] (__amethystora_pkg_containers); and contains -- $words[3] $argv
end

complete -c amethystora-pkg -f
complete -c amethystora-pkg -n __fish_use_subcommand -a containers -d 'The containers it manages'
complete -c amethystora-pkg -n __fish_use_subcommand -a templates -d 'What a new container starts from'
complete -c amethystora-pkg -n __fish_use_subcommand -a managers -d 'The commands a package manager is driven by'
complete -c amethystora-pkg -n __fish_use_subcommand -a install -d 'Install a .deb, .rpm or .pkg.tar.zst file'
complete -c amethystora-pkg -n __fish_use_subcommand -a upgrade-all -d 'Upgrade every container'
complete -c amethystora-pkg -n __fish_use_subcommand -a '(__amethystora_pkg_containers)' -d Container

complete -c amethystora-pkg -n '__amethystora_pkg_first containers; and not __fish_seen_subcommand_from list new rm reset' \
    -a 'list new rm reset'
complete -c amethystora-pkg -n '__amethystora_pkg_first containers; and __fish_seen_subcommand_from rm reset' \
    -a '(__amethystora_pkg_containers)' -l force
complete -c amethystora-pkg -n '__amethystora_pkg_first containers; and __fish_seen_subcommand_from new' \
    -l template -x -a '(__amethystora_pkg_names templates)'
complete -c amethystora-pkg -n '__amethystora_pkg_first containers; and __fish_seen_subcommand_from new' -l name -x
complete -c amethystora-pkg -n '__amethystora_pkg_first containers; and __fish_seen_subcommand_from new' \
    -l home -x -a '(__fish_complete_directories)'
complete -c amethystora-pkg -n '__amethystora_pkg_first containers; and __fish_seen_subcommand_from new' -l init -l no-prompt
complete -c amethystora-pkg -n '__fish_seen_subcommand_from list' -l json

for kind in templates managers
    complete -c amethystora-pkg -n "__amethystora_pkg_first $kind; and not __fish_seen_subcommand_from list show new update rm export import" \
        -a 'list show new update rm export import'
    complete -c amethystora-pkg -n "__amethystora_pkg_first $kind; and __fish_seen_subcommand_from show rm export update" \
        -a "(__amethystora_pkg_names $kind)"
    complete -c amethystora-pkg -n "__amethystora_pkg_first $kind; and __fish_seen_subcommand_from import" -F
    complete -c amethystora-pkg -n "__amethystora_pkg_first $kind; and __fish_seen_subcommand_from export" -l output -r -F
    complete -c amethystora-pkg -n "__amethystora_pkg_first $kind; and __fish_seen_subcommand_from new update" -l name -x
    complete -c amethystora-pkg -n "__amethystora_pkg_first $kind; and __fish_seen_subcommand_from new update" -l no-prompt
end
complete -c amethystora-pkg -n '__amethystora_pkg_first templates; and __fish_seen_subcommand_from new update' \
    -l base -x
complete -c amethystora-pkg -n '__amethystora_pkg_first templates; and __fish_seen_subcommand_from new update' \
    -l packages -x
complete -c amethystora-pkg -n '__amethystora_pkg_first templates; and __fish_seen_subcommand_from new update' \
    -l pkg-manager -x -a '(__amethystora_pkg_names managers)'
complete -c amethystora-pkg -n '__amethystora_pkg_first templates; and __fish_seen_subcommand_from new update' \
    -l unshare -x -a 'ipc netns process devsys groups all'
complete -c amethystora-pkg -n '__amethystora_pkg_first templates; and __fish_seen_subcommand_from new update' \
    -l description -x
complete -c amethystora-pkg -n '__amethystora_pkg_first templates; and __fish_seen_subcommand_from new update' \
    -l own-home
for option in need-sudo install remove purge search show list update upgrade autoremove clean noconfirm
    complete -c amethystora-pkg -n '__amethystora_pkg_first managers; and __fish_seen_subcommand_from new update' \
        -l $option -x
end

complete -c amethystora-pkg -n '__amethystora_pkg_first install' -F
complete -c amethystora-pkg -n '__amethystora_pkg_first install' -l yes -l no-export

complete -c amethystora-pkg -n __amethystora_pkg_in_container \
    -a 'enter run start stop install remove purge search show list update upgrade autoremove clean export unexport'
complete -c amethystora-pkg -n '__amethystora_pkg_container_doing export unexport' -l app -x
complete -c amethystora-pkg -n '__amethystora_pkg_container_doing export unexport' -l bin -r -F
complete -c amethystora-pkg -n '__amethystora_pkg_container_doing export unexport' -l bin-output -x -a '(__fish_complete_directories)'
complete -c amethystora-pkg -n '__amethystora_pkg_container_doing install' -l no-export -l yes
complete -c amethystora-pkg -n '__amethystora_pkg_container_doing remove purge upgrade' -l yes
