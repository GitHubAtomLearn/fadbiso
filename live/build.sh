#! /usr/bin/env bash

set -euo pipefail
set -x
export FORCE_COLUMNS=134

function main() {

    variant="${VARIANT:-silverblue}"

    # Remove unnecessary repos.
    local -r unnecessary_repos=(
        "rpmfusion-nonfree-steam.repo"
        "rpmfusion-nonfree-nvidia-driver.repo"
        "google-chrome.repo"
        "fedora-cisco-openh264.repo"
        "_copr:copr.fedorainfracloud.org:phracek:PyCharm.repo"
    )
    for repo in ${unnecessary_repos[@]}; do
        rm --force /etc/yum.repos.d/${repo}
    done
    ls -lathr /etc/yum.repos.d

    # Swap `nano` for `vim`
    dnf swap --assumeyes --refresh --allowerasing nano vim-default-editor

    # Upgrade installed packages.
    dnf upgrade \
        --enablerepo=updates-testing \
        --assumeyes \
        --refresh \
        --no-allow-downgrade \
        --allowerasing

    # Create the directory that `/root` is symlinked to.
    mkdir --parents "$(realpath /root)"

    # bwrap tries to write `/proc/sys/user/max_user_namespaces`
    # which is mounted as `ro`, so we need to remount it as `rw`.
    mount --options remount,rw /proc/sys

    function dnf_install() {
        dnf --assumeyes --refresh install \
        --allowerasing \
        --no-allow-downgrade \
        --enablerepo=updates-testing \
        --exclude container-selinux \
        "${@}"
    }

    # `image-builder` needs `gcdx64.efi`.
    dnf_install grub2-efi-x64-cdboot

    # `image-builder` expects the EFI directory to be in `/boot/efi`.
    mkdir --parents /boot/efi
    cp --verbose --archive /usr/lib/efi/*/*/EFI /boot/efi/

    # Needed for `image-builder`'s buildroot.
    dnf_install xorriso isomd5sum squashfs-tools

    # Install `sbctl`.
    # https://github.com/Foxboron/sbctl
    dnf --assumeyes copr enable chenxiaolong/sbctl
    dnf_install sbctl

    # Install `dracut-live` and regenerate the initramfs.
    dnf_install dracut-live
    kernel=$(kernel-install list --json pretty | jq --raw-output '.[] | select(.has_kernel == true) | .version')
    DRACUT_NO_XATTR=1 dracut \
        --verbose \
        --force \
        --zstd \
        --reproducible \
        --no-hostonly \
        --add "dmsquash-live \
            dmsquash-live-autooverlay" \
        "/usr/lib/modules/${kernel}/initramfs.img" \
        "${kernel}"

    # Install `livesys-scripts` and configure them.
    dnf_install livesys-scripts

    # Set session and label based on variant.
    if [[ "${variant}" == "silverblue" ]]; then
        sed --in-place "s/^livesys_session=.*/livesys_session=gnome/" /etc/sysconfig/livesys
        iso_label="Silverblue-Live"
    elif [[ "${variant}" == "kinoite" ]]; then
        sed --in-place "s/^livesys_session=.*/livesys_session=kde/" /etc/sysconfig/livesys
        iso_label="Kinoite-Live"
    fi

    systemctl enable livesys.service livesys-late.service

    # Some configuration for the ISO.
    # Set the defaults for `image-builder`.
    mkdir --parents /usr/lib/image-builder/bootc

    # Generate `iso.yaml` from template.
    cat > /usr/lib/image-builder/bootc/iso.yaml <<EOF
label: "${iso_label}"
grub2:
  timeout: 10
  entries:
    - name: "Fedora ${iso_label}"
      linux: "/images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=${iso_label} enforcing=0 rd.live.image"
      initrd: "/images/pxeboot/initrd.img"
EOF

    # Cleanup.
    dnf clean all

    # Remove GNOME-related packages.
    if [[ "${variant}" == "silverblue" ]]; then
        rpm --erase --nodeps \
            yelp \
            gnome-tour
    fi

    rm --force /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:chenxiaolong:sbctl.repo

    rm --recursive --force /var /tmp
    mkdir /var /tmp
    bootc container lint \
        --no-truncate \
        --skip nonempty-boot \
        --skip baseimage-root

}
main "${@}"
