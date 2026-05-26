ARG REGISTRY=overridden
ARG VARIANT=overridden
ARG VERSION=overridden
ARG CHUNKAH_IMAGE=overridden

FROM ${REGISTRY}/${VARIANT}:${VERSION} AS builder

ARG REGISTRY
ARG VARIANT
ARG VERSION
ARG SRC_PATH=overridden

ENV REGISTRY=${REGISTRY}
ENV VARIANT=${VARIANT}
ENV VERSION=${VERSION}

RUN --mount=type=bind,source=${SRC_PATH},target=/src,ro \
    /src/build.sh

# Rechunk container image
# - Use more layers (128)
# - Ignore legacy ostree folders

FROM ${CHUNKAH_IMAGE} AS chunkah

RUN --mount=from=builder,src=/,target=/chunkah,ro \
    --mount=type=bind,target=/run/src,rw \
        chunkah build \
            --verbose \
            --max-layers 128 \
            --prune /ostree \
            --prune /sysroot/ostree \
            > /run/src/iso.ociarchive

FROM oci-archive:iso.ociarchive
