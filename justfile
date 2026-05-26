# Default container repository for base images
repository_standard := "quay.io/fedora-ostree-desktops"

# Sealed container repository for security-hardened builds
repository_sealed := "quay.io/fedora-atomic-desktops-sealed"

# Default filesystem for bootc ISO builds
bootc_default_fs := "btrfs"

# osbuild image type for ISO generation
image_type := "bootc-generic-iso"

# Chunkah container image for layer optimization
chunkah_repository := "quay.io/coreos/chunkah"
chunkah_tag := "dev"
chunkah_image := chunkah_repository + ":" + chunkah_tag

# `image_builder_cli` image for ISO generation
# image_builder_cli := "ghcr.io/osbuild/image-builder-cli:latest"
image_builder_cli := "ghcr.io/osbuild/image-builder-cli:sha-fac520602df59b6c79189daf05fb6a2acf9a9eea"

# Output directory for generated ISOs
output_dir := "./output"

all:
    @echo "Please read README.md"

# Build container image
[arg('type', pattern='installer|live')]
[arg('repo', pattern='standard|sealed')]
[arg('variant', pattern='silverblue|kinoite')]
[arg('version', pattern='44|45')]
container type repo variant version:
    #! /usr/bin/env bash
    set -euo pipefail
    set -x
    export FORCE_COLUMNS=134

    function main() {
        if [[ "${EUID}" -ne 0 ]]; then
            echo -e "\nRoot access is required to perform actions on bootable containers.\n" >&2
            exit 1
        fi

        local repository
        if [[ "{{repo}}" == "standard" ]]; then
            repository="{{repository_standard}}"
        elif [[ "{{repo}}" == "sealed" ]]; then
            repository="{{repository_sealed}}"
        fi

        local -r container_tag="localhost/fedora-{{variant}}-iso:{{version}}"

        podman image build \
            --pull=newer \
            --cap-add sys_admin \
            --security-opt label=type:unconfined_t \
            --build-arg REGISTRY="${repository}" \
            --build-arg VARIANT={{variant}} \
            --build-arg VERSION={{version}} \
            --build-arg SRC_PATH="{{type}}" \
            --build-arg CHUNKAH_IMAGE="{{chunkah_image}}" \
            --skip-unused-stages=false \
            --volume ${PWD}:/run/src \
            --tag "${container_tag}" \
            --file ./Containerfile

        # Cleanup temporary files and images
        rm --force ./iso.ociarchive
        just cleanup

    }
    main "${@}"

# Build ISO from container image
[arg('variant', pattern='silverblue|kinoite')]
[arg('version', pattern='44|45')]
iso variant version:
    #! /usr/bin/env bash
    set -euo pipefail
    set -x
    export FORCE_COLUMNS=134

    function main() {
        if [[ "${EUID}" -ne 0 ]]; then
            echo -e "\nRoot access is required to perform actions on bootable containers.\n" >&2
            exit 1
        fi

        [[ ! -d "{{output_dir}}" ]] && mkdir --parents "{{output_dir}}"

        local -r bootc_ref="localhost/fedora-{{variant}}-iso:{{version}}"

        podman container run \
            --pull=newer \
            --rm \
            --privileged \
            --security-opt label=type:unconfined_t \
            --volume /var/lib/containers/storage:/var/lib/containers/storage \
            --volume {{output_dir}}:/output \
            {{image_builder_cli}} \
                build \
                --output-dir /output \
                --bootc-ref ${bootc_ref} \
                --bootc-default-fs {{bootc_default_fs}} \
                {{image_type}}

        chown --changes --recursive ${SUDO_USER}: {{output_dir}}

        # Cleanup temporary images
        just cleanup

    }
    main "${@}"

# Cleanup temporary images and build cache
cleanup:
    #! /usr/bin/env bash
    podman image prune --external --force
    podman image prune --build-cache --force
    podman images
