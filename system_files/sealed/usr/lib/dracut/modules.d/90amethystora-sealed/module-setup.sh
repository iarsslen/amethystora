#!/usr/bin/bash
# The sealed initramfs's own check (build_files/sealed/00-sealed.sh adds it with bootc's module): the
# system starts only if the composefs root bootc mounted has fs-verity required, see
# amethystora-sealed-verity.

check() {
    return 255
}

depends() {
    echo bootc
}

install() {
    local service=amethystora-sealed-verity.service
    inst_script "${moddir}/amethystora-sealed-verity" /usr/lib/amethystora/amethystora-sealed-verity
    inst_simple "${moddir}/${service}" "${systemdsystemunitdir}/${service}"
    mkdir -p "${initdir}${systemdsystemunitdir}/initrd-root-fs.target.wants"
    ln_r "${systemdsystemunitdir}/${service}" "${systemdsystemunitdir}/initrd-root-fs.target.wants/${service}"
}
