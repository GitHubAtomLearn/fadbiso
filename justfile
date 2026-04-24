# Fedora version
# version := "44"

# Default container repository for base images
repository_standard := "quay.io/fedora-ostree-desktops"

# Sealed container repository for security-hardened builds
repository_sealed := "quay.io/fedora-atomic-desktops-sealed"

# Container image tag base
# container_tag := "localhost/fedora-" + version + "-iso:" + version

# Reference to the chunked bootable container image
# bootc_ref := "{{container_tag}}-chunked"

# Default filesystem for bootc ISO builds
bootc_default_fs := "btrfs"

# osbuild image type for ISO generation
image_type := "bootc-generic-iso"

# Chunkah container image for layer optimization
chunkah_repository := "quay.io/coreos/chunkah"
chunkah_tag := "dev"
chunkah_image := chunkah_repository + ":" + chunkah_tag

# `image_builder_cli` image for ISO generation
image_builder_cli := "ghcr.io/osbuild/image-builder-cli:latest"

# Output directory for generated ISOs
output_dir := "./output"

all:
    @echo "Please read README.md"

# Build container image
# Usage: just container installer silverblue 44
#        just container live kinoite sealed 45
[arg('type', pattern='installer|live')]
[arg('variant', pattern='silverblue|kinoite')]
[arg('repo', pattern='standard|sealed')]
[arg('version', pattern='44|45')]
container type variant repo="standard" version="44":
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
            --tag "${container_tag}" \
            --file ./Containerfile

        # Rechunk with Chunkah for optimized layers
        local -r chunkah_tmp_image="{{variant}}.ociarchive"
        local -r chunked_image="${container_tag}-chunked"
        local -r chunkah_config_str=$(podman inspect "${container_tag}")

        podman container run \
            --pull=newer \
            --rm \
            --name chunkah \
            --mount=type=image,src="${container_tag}",target=/chunkah \
            --env CHUNKAH_CONFIG_STR="${chunkah_config_str}" \
            {{chunkah_image}} \
                build \
                    --verbose \
                    --prune /sysroot/ \
                    --max-layers 128 \
                    --label ostree.commit- \
                    --label ostree.final-diffid- \
                    --skip-special-files \
                    > ${chunkah_tmp_image}

        local iid=$(podman image load --input ${chunkah_tmp_image})
        local -r iid=${iid#*sha256:}
        podman image tag "${iid}" "${chunked_image}"

        # Cleanup temporary files and images
        rm --force ${chunkah_tmp_image}
        just cleanup

    }
    main "${@}"

# Build ISO from container image
# Usage: just iso silverblue
#        just iso kinoite
[arg('variant', pattern='silverblue|kinoite')]
[arg('version', pattern='44|45')]
iso variant version="44":
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

        local -r bootc_ref="localhost/fedora-{{variant}}-iso:{{version}}-chunked"

        podman container run \
            --pull=newer \
            --rm \
            --privileged \
            --security-opt label=type:unconfined_t \
            --volume /var/lib/containers/storage:/var/lib/containers/storage \
            --volume ./output:/output \
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
