# Rendered from the current Amethystora theme. Drop a starship.toml of your own into the theme
# directory (~/.config/amethystora/themes/<theme>/) to replace it, or write ~/.config/starship.toml
# and Amethystora will leave that file alone.

format = """
$directory\
$git_branch\
$git_status\
$python\
$nodejs\
$rust\
$golang\
$container\
$cmd_duration\
$line_break\
$character"""

palette = "amethystora"

[palettes.amethystora]
accent = "{{ accent }}"
muted = "{{ color8 }}"
added = "{{ color2 }}"
changed = "{{ color3 }}"
removed = "{{ color1 }}"
info = "{{ color6 }}"
alt = "{{ color5 }}"

[directory]
style = "bold accent"
truncation_length = 3
truncate_to_repo = true

[character]
success_symbol = "[❯](bold accent)"
error_symbol = "[❯](bold removed)"
vimcmd_symbol = "[❮](bold info)"

[git_branch]
symbol = " "
style = "alt"
format = "[on ](muted)[$symbol$branch]($style) "

[git_status]
style = "changed"
format = '([\[$all_status$ahead_behind\]]($style) )'

[cmd_duration]
min_time = 2000
style = "muted"
format = "[took $duration]($style) "

[python]
symbol = " "
style = "info"

[nodejs]
symbol = " "
style = "added"

[rust]
symbol = " "
style = "changed"

[golang]
symbol = " "
style = "info"

[container]
style = "muted"
format = '[$symbol \[$name\]]($style) '
