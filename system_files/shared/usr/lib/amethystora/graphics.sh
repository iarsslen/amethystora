# shellcheck shell=bash
# Sourced by the login screen (amethystora-greeter) and the Hyprland session (amethystora-hyprland-session).
# Hyprland and DankMaterialShell need a GPU. VirtualBox has none that works: even with 3D acceleration
# enabled, Mesa's VMware driver fails to create a screen there, Hyprland crashes and the screen stays black.
# In VirtualBox, and in any other VM without a GPU render node, render in software instead.
# VMs with working 3D (VMware, QEMU with virgl) and real hardware keep GPU rendering.

amethystora_needs_software_rendering() {
    local virt
    virt="$(systemd-detect-virt --vm 2>/dev/null)" || return 1
    [[ "${virt}" == oracle ]] || ! compgen -G '/dev/dri/renderD*' >/dev/null
}

if amethystora_needs_software_rendering; then
    export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
    export QT_QUICK_BACKEND="${QT_QUICK_BACKEND:-software}"
fi
