# Based on tModLoader's official Dockerfile:
# https://github.com/tModLoader/tModLoader/tree/1.4.4/patches/tModLoader/Terraria/release_extras/DedicatedServerUtils/Dockerfile
# Only the final ENTRYPOINT is replaced with our wrapper.

# Force amd64 throughout: tModLoader/SteamCMD have no ARM support, so even on
# ARM build hosts (e.g. Railway's Metal builder) we emulate amd64 via QEMU.
FROM --platform=linux/amd64 ubuntu:22.04 AS builder

ARG DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture i386 \
 && apt-get update -y \
 && apt-get install -y --no-install-recommends libc6:i386 \
 && rm -rf /var/lib/apt/lists/*

# Stage that materializes Git LFS objects into real binaries. Railway's git
# clone doesn't smudge LFS files automatically, so the .tmod files in the
# build context arrive as ~130-byte pointer text files instead of real .tmod
# binaries. We pull them here so the final image has actual mod content.
FROM --platform=linux/amd64 alpine:3.20 AS lfs-puller
RUN apk add --no-cache git git-lfs ca-certificates
WORKDIR /repo
# Copy the entire build context (including .git/) so git-lfs has the LFS
# pointer metadata and remote info it needs to fetch from GitHub.
COPY . /repo/
# Run a checkout of HEAD to force LFS smudge. `git lfs pull` is idempotent
# and only downloads objects that are actually pointers in the working tree.
RUN git lfs install --local \
    && git lfs pull \
    && echo "=== LFS materialization check ===" \
    && for f in /repo/preload/Mods/*.tmod; do \
         hdr=$(head -c 4 "$f"); \
         if [ "$hdr" != "TMOD" ]; then \
             echo "ERROR: $f is still an LFS pointer (header=$hdr)" >&2; \
             exit 1; \
         fi; \
       done \
    && echo "=== All .tmod files have valid TMOD headers ==="

FROM --platform=linux/amd64 alpine:3.20

RUN apk update \
    && apk add --no-cache bash curl nano file libgcc libstdc++ icu-libs unzip \
    && rm -rf /var/cache/apk/*

COPY --from=builder \
    /lib/i386-linux-gnu/ld-linux.so.2 \
    /lib/i386-linux-gnu/libc.so.6 \
    /lib/i386-linux-gnu/libdl.so.2 \
    /lib/i386-linux-gnu/libm.so.6 \
    /lib/i386-linux-gnu/libpthread.so.0 \
    /lib/i386-linux-gnu/librt.so.1 \
    /lib/

ARG UID=1000
ARG GID=1000
ENV UMASK=0002

ARG TMLVERSION

RUN addgroup -g $GID tml \
    && adduser -D --home /home/tml -u $UID -G tml tml

USER tml
ENV HOME=/home/tml
ENV USER=tml
ENV PATH="$PATH:$HOME/.bin"
WORKDIR $HOME

RUN mkdir -p ~/Steam ~/.bin \
    && curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C ~/Steam

COPY --chown=tml:tml --chmod=0755 <<EOF ./.bin/steamcmd
#!/bin/bash

exec ~/Steam/steamcmd.sh "\$@"
EOF

# Note: the official Dockerfile runs `RUN steamcmd +quit` here to pre-update
# SteamCMD at build time. We skip it because that step requires executing the
# 32-bit `linux32/steamcmd` binary in the builder, which fails on hosts without
# i386 multiarch support (e.g. Railway's ARM-based Metal builder running amd64
# via QEMU). SteamCMD will self-update on first runtime use instead.

ADD --chown=tml:tml --chmod=0755 https://raw.githubusercontent.com/tModLoader/tModLoader/1.4.4/patches/tModLoader/Terraria/release_extras/DedicatedServerUtils/manage-tModLoaderServer.sh .

RUN ISDOCKER=1 ./manage-tModLoaderServer.sh install-tml --github

COPY --chown=tml:tml --chmod=0755 entrypoint-wrapper.sh /home/tml/entrypoint-wrapper.sh

# Bundled mod files seeded into the volume on first run (see seed_mods_from_preload).
# All 14 .tmod files (workshop + local) + enabled.json. Pulled from the
# lfs-puller stage so the binaries are real, not LFS pointer files.
COPY --chown=tml:tml --from=lfs-puller /repo/preload /preload

EXPOSE 7777

ENTRYPOINT [ "/home/tml/entrypoint-wrapper.sh" ]
