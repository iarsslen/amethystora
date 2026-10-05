# vim: set ft=make :

set default-list

# Write this machine's setup to ~/.config/amethystora/setup.json, or to FILE ("-" prints it)
[no-cd]
[no-exit-message]
[positional-arguments]
save *FILE:
    @/usr/libexec/amethystora-setup save "$@"

# What this machine and the setup file disagree on, changing nothing (--json for scripts)
[no-cd]
[no-exit-message]
[positional-arguments]
diff *ARGS:
    @/usr/libexec/amethystora-setup diff "$@"

# Add and set what the setup file names, after showing it (--remove also takes away what it does not)
[no-cd]
[no-exit-message]
[positional-arguments]
apply *ARGS:
    @/usr/libexec/amethystora-setup apply "$@"
