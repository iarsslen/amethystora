# Completion for ame (/usr/bin/ame): a group or a command first, then the commands in the group.
# `ame pkg` completes as amethystora-pkg does.

function __ame_in_pkg
    set -l words (commandline -opc)
    test (count $words) -ge 2; and test "$words[2]" = pkg
end

# ame --summary names every command, those in a group as group::command
function __ame_names
    set -l words (commandline -opc)
    set -l names (ame --summary 2>/dev/null | string split ' ')
    switch (count $words)
        case 1
            string replace -r '::.*' '' -- $names | sort -u
        case 2
            string replace -rf "^$words[2]::" '' -- $names
    end
end

# The rest, as if amethystora-pkg had been typed
function __ame_pkg
    set -l words (commandline -opc)
    set -e words[1..2]
    complete -C "amethystora-pkg $words "(commandline -ct)
end

complete -c ame -f
complete -c ame -n 'not __ame_in_pkg' -a '(__ame_names)'
complete -c ame -n __ame_in_pkg -a '(__ame_pkg)'
