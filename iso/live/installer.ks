# What the installer in the live session installs: the image the live system carries a copy of
# (iso/live/build.sh puts it in the read-only image store), so that installing needs no network.
# build.sh replaces @IMAGE@ with the image the ISO was built from.
ostreecontainer --url=@IMAGE@ --transport=containers-storage --no-signature-verification

# Then the installed machine follows that image in the registry rather than the copy, as one installed
# from the installer ISO does (iso/iso.toml), and amethystora-signed-updates switches it to
# signature-checked updates at its first boot
%post --erroronfail
bootc switch --mutate-in-place --transport registry @IMAGE@
%end
