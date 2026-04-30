#! /usr/bin/env bash

set -euo pipefail
set -x
export FORCE_COLUMNS=134

function main() {

    # variant="${VARIANT:-silverblue}"
    # registry_source="${registry_source:-default}"

    dnf install --assumeyes \
        anaconda \
        anaconda-install-img-deps \
        anaconda-dracut \
        dracut-config-generic \
        dracut-network \
        net-tools \
        grub2-efi-x64-cdboot \
        plymouth \
        default-fonts-core-sans \
        default-fonts-other-sans \
        google-noto-sans-cjk-fonts \
        xorrisofs \
        squashfs-tools

    mkdir --parents /boot/efi
    cp --recursive --archive /usr/lib/efi/*/*/EFI /boot/efi

    # These things are normally performed by `lorax` to make `anaconda` work.
    # This is the bare minimum to get things to work.
    echo "install:x:0:0:root:/root:/usr/libexec/anaconda/run-anaconda" >> /etc/passwd
    echo "install::14438:0:99999:7:::" >> /etc/shadow
    passwd --delete root

    mv /usr/share/anaconda/list-harddrives-stub /usr/bin/list-harddrives
    mv /etc/yum.repos.d /etc/anaconda.repos.d
    ln --symbolic /lib/systemd/system/anaconda.target /etc/systemd/system/default.target
    rm --verbose /usr/lib/systemd/system-generators/systemd-gpt-auto-generator

    rm --verbose /usr/lib/systemd/system/autovt@.service
    # ln: failed to create symbolic link '/usr/lib/systemd/system/autovt@.service': File exists
    # Simon de Vlieger:
    # Yea I've seen that; on some containers that symlink already exists and on others it doesn't.
    # Probably a conditional remove if it exists before the `ln` works best?
    # At least for now.
    ln --symbolic /usr/lib/systemd/system/anaconda-shell@.service /usr/lib/systemd/system/autovt@.service

    mkdir /usr/lib/systemd/logind.conf.d
    echo -e "[Login]\nReserveVT=2" > /usr/lib/systemd/logind.conf.d/anaconda-shell.conf

    # Regenerate the initramfs including the anaconda module.
    mkdir "$(realpath /root)"
    kernel=$(kernel-install list --json pretty | jq --raw-output '.[] | select(.has_kernel == true) | .version')
    DRACUT_NO_XATTR=1 dracut \
        --verbose \
        --force \
        --zstd \
        --reproducible \
        --no-hostonly \
        --add "anaconda" \
        "/usr/lib/modules/${kernel}/initramfs.img" "${kernel}"

    mkdir /etc/systemd/user/pipewire.service.d/
    echo -e "[Unit]\nConditionUser=" > /etc/systemd/user/pipewire.service.d/allowroot.conf

    mkdir /etc/systemd/user/pipewire.socket.d/
    echo -e "[Unit]\nConditionUser=" > /etc/systemd/user/pipewire.socket.d/allowroot.conf

    # Some configuration for anaconda.
    # Set the defaults for anaconda.
    # This includes the container that will be installed onto the system.

    # Determine the registry path and ISO label based on source
    # Determine the registry path based on registry_source
    # if [[ "${registry_source}" == "sealed" ]]; then
    #     registry_path="quay.io/fedora-atomic-desktops-sealed"
    # else
    #     registry_path="quay.io/fedora-ostree-desktops"
    # fi

    # echo "REGISTRY=${REGISTRY}"
    # echo "VARIANT=${VARIANT}"
    # echo "VERSION=${VERSION}"


    cat > /usr/share/anaconda/interactive-defaults.ks <<EOF
bootc --source-imgref registry:${REGISTRY}/${VARIANT}:${VERSION} --target-imgref ${REGISTRY}/${VARIANT}:${VERSION}
EOF
# bootc --source-imgref registry:${REGISTRY}/${variant}:${VERSION} --target-imgref ${REGISTRY}/${variant}:${VERSION}

    # Some configuration for the ISO.
    # Set the defaults for (bootc-)image-builder.
    mkdir --parents /usr/lib/image-builder/bootc

    # Set label based on variant.

    # if [[ "${variant}" == "kinoite" ]]; then
    #     iso_label="Kinoite"
    # else
    #     iso_label="Silverblue"
    # fi

    if [[ "${VARIANT}" == "silverblue" ]]; then
        iso_label="Silverblue"
    elif [[ "${VARIANT}" == "kinoite" ]]; then
        iso_label="Kinoite"
    elif [[ "${VARIANT}" == "sway-atomic" ]]; then
        iso_label="Sway"
    fi

    # if [[ "${source}" == "sealed" ]]; then
    #     iso_label="${iso_label} Sealed"
    # fi

    # Generate iso.yaml from template.
    cat > /usr/lib/image-builder/bootc/iso.yaml <<EOF
label: "${iso_label}-Installer"
grub2:
  timeout: 10
  entries:
    - name: "Install Fedora ${iso_label}"
      linux: "/images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=${iso_label}-Installer enforcing=0 rd.live.image"
      initrd: "/images/pxeboot/initrd.img"
EOF

    # Cleanup.
    dnf clean all

    rm --recursive --force /var /tmp
    mkdir /var /tmp
    bootc container lint \
        --no-truncate \
        --skip nonempty-boot \
        --skip baseimage-root

}
main "${@}"
