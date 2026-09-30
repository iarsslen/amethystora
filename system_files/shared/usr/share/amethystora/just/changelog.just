# vim: set ft=make :

alias changelog := changelogs

# Show the changelog
changelogs:
    #!/usr/bin/bash

    # Get Image Tag
    TAG="$(jq -r '.["image-tag"]' < /usr/share/amethystora/image-info.json)"

    # If stable or gts, get changelogs from Github Releases
    if [[ "$TAG" =~ gts$|stable$ ]]; then
        DATE="$(grep -oP "OSTREE_VERSION=.*\d{2}\.\K\d{8}[.0-9]*" /etc/os-release)"
        CONTENT="$(curl -Ls "https://api.github.com/repos/amethystora/amethystora/releases" | jq -r ".[] | select(.tag_name==\"${TAG}-${DATE}\") | .body")"
    fi

    # Display Content with Glow, otherwise fallback to rpm-ostree changelogs (stable-daily/latest/desynced)
    if [[ -n "${CONTENT:-}" ]]; then
        echo "$CONTENT" | glow -p
    else
        echo "WARN: Could not find a release specific to your image"
        curl -Ls "https://api.github.com/repos/amethystora/amethystora/releases/latest" | jq -r ".body" | glow -p
    fi
