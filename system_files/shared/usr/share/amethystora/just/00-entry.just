set allow-duplicate-recipes := true
set ignore-comments := true

_default:
    #!/usr/bin/bash
    echo "https://github.com/iarsslen/amethystora#readme"
    ujust --list --list-heading $'Available commands:\n' --list-prefix $' - '

# Imports

import "/usr/share/amethystora/just/apps.just"
import "/usr/share/amethystora/just/changelog.just"
import "/usr/share/amethystora/just/default.just"
import "/usr/share/amethystora/just/shared.just"
import "/usr/share/amethystora/just/system.just"
import "/usr/share/amethystora/just/update.just"
import? "/usr/share/amethystora/just/60-custom.just"
