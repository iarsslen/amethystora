# What the installer in the live session installs: the image the live system carries a copy of
# (iso/live/build.sh puts it in the read-only image store), so that installing needs no network.
# build.sh replaces @IMAGE@ with the image the ISO was built from.
ostreecontainer --url=@IMAGE@ --transport=containers-storage --no-signature-verification

# Then the installed machine follows that image in the registry rather than the copy, signature-checked
# from its first update, as one installed from the installer ISO does (iso/iso.toml). build.sh fails on
# a switch without the flag. The marker tells the first boot that this is a new installation, which gets
# the hourly snapshots of the home folders (system-setup.hooks.d/26-snapshots-new-installation.sh).
%post --erroronfail
bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry @IMAGE@
mkdir -p /var/lib/amethystora && touch /var/lib/amethystora/new-installation
%end
