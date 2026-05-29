#! /usr/bin/env bash

set -euo pipefail
set -x
export FORCE_COLUMNS=134

function main() {

    src_path="${SRC_PATH}"
    variant="${VARIANT}"

    # Upgrade installed packages.
    rm --force /etc/yum.repos.d/fedora-cisco-openh264.repo
    dnf upgrade \
        --enablerepo=updates-testing \
        --assumeyes \
        --refresh \
        --no-allow-downgrade \
        --allowerasing

    # Install required packages.
    dnf --assumeyes --refresh install \
    --allowerasing \
    --no-allow-downgrade \
    --enablerepo=updates-testing \
    --no-docs --setopt=tsflags=nodocs \
    --best \
    --exclude container-selinux \
        $(grep --extended-regexp --invert-match '^#|^$' /src/payload-packages.txt)

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

    rm --verbose --force /usr/lib/systemd/system/autovt@.service
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
        "/usr/lib/modules/${kernel}/initramfs.img" \
        "${kernel}"

    mkdir /etc/systemd/user/pipewire.service.d/
    echo -e "[Unit]\nConditionUser=" > /etc/systemd/user/pipewire.service.d/allowroot.conf

    mkdir /etc/systemd/user/pipewire.socket.d/
    echo -e "[Unit]\nConditionUser=" > /etc/systemd/user/pipewire.socket.d/allowroot.conf

    # Some configuration for anaconda.
    # Set the defaults for anaconda.
    # This includes the container that will be installed onto the system.

    # Determine the registry path and ISO label based on source
    # Determine the registry path based on registry_source
    cat > /usr/share/anaconda/interactive-defaults.ks <<EOF
bootc --source-imgref registry:${REGISTRY}/${VARIANT}:${VERSION} --target-imgref ${REGISTRY}/${VARIANT}:${VERSION}
EOF

    # Some configuration for the ISO.
    # Set the defaults for (bootc-)image-builder.
    mkdir --parents /usr/lib/image-builder/bootc

    # Set label based on variant.

    if [[ "${VARIANT}" == "silverblue" ]]; then
        iso_label="Silverblue"
    elif [[ "${VARIANT}" == "kinoite" ]]; then
        iso_label="Kinoite"
    elif [[ "${VARIANT}" == "fedora-bootc" ]]; then
        iso_label="bootc"
    fi

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
        --skip baseimage-root \
        --skip nonempty-run-tmp

}
main "${@}"
