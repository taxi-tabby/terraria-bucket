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
# preload/Mods/ contains all 14 .tmod files:
#   - 12 files are stored as regular git blobs (each <100MB).
#   - 2 large files (CalamityMod ~110MB, CalamityModMusic ~180MB) are tracked
#     via Git LFS because they exceed GitHub's 100MB-per-file limit.
#
# Railway's git clone doesn't pull LFS objects, so the build context arrives
# with ~130-byte LFS pointer text files instead of the real binaries for the
# two LFS-tracked mods. After COPY, fetch the real content from GitHub's
# media endpoint (which serves the LFS-resolved binary directly, with no
# auth needed since the repo is public).
COPY --chown=tml:tml preload /preload

# Repo-specific URL prefix. Override with --build-arg if you fork this repo.
ARG GH_LFS_BASE="https://media.githubusercontent.com/media/taxi-tabby/terraria-bucket/main"

RUN echo "[build] fetching LFS-tracked mods from GitHub media endpoint..." \
    && curl -fL --retry 3 \
        "$GH_LFS_BASE/preload/Mods/CalamityMod.tmod" \
        -o /preload/Mods/CalamityMod.tmod \
    && curl -fL --retry 3 \
        "$GH_LFS_BASE/preload/Mods/CalamityModMusic.tmod" \
        -o /preload/Mods/CalamityModMusic.tmod \
    && echo "[build] verifying all 14 .tmod files are real binaries..." \
    && for f in /preload/Mods/*.tmod; do \
         hdr=$(head -c 4 "$f"); \
         if [ "$hdr" != "TMOD" ]; then \
             echo "[build] FATAL: $f is not a real .tmod (header=$hdr, $(wc -c <"$f") bytes)"; \
             echo "[build]   For files outside LFS this means the git blob is wrong."; \
             echo "[build]   For LFS-tracked files this means the media URL fetch failed or"; \
             echo "[build]   the LFS object isn't on GitHub yet — push the LFS objects first."; \
             exit 1; \
         fi; \
       done \
    && echo "[build] all 14 .tmod files have valid TMOD headers"

EXPOSE 7777

ENTRYPOINT [ "/home/tml/entrypoint-wrapper.sh" ]
