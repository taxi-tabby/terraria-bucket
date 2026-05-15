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
# preload/Mods/ contains 12 .tmod files that fit under GitHub's 100MB-per-file
# limit (regular git blobs, no LFS).
COPY --chown=tml:tml preload /preload

# The two largest workshop mods exceed GitHub's 100MB-per-file limit:
#   - CalamityMod.tmod (~110MB)
#   - CalamityModMusic.tmod (~180MB)
# They cannot live in the git repo, so fetch them at build time from URLs
# the user provides via Railway service variables (which Railway exposes as
# Docker build args). If a URL isn't set the mod just won't be bundled.
#
# To set up: upload the files anywhere with a stable public URL (GitHub
# Releases on a public repo works well, no auth needed), then set
# CALAMITY_MOD_URL and CALAMITY_MUSIC_URL in Railway's Variables tab.
ARG CALAMITY_MOD_URL=""
ARG CALAMITY_MUSIC_URL=""
RUN if [ -n "$CALAMITY_MOD_URL" ]; then \
        echo "[build] fetching CalamityMod.tmod from $CALAMITY_MOD_URL..."; \
        curl -fL --retry 3 "$CALAMITY_MOD_URL" -o /preload/Mods/CalamityMod.tmod \
            && [ "$(head -c 4 /preload/Mods/CalamityMod.tmod)" = "TMOD" ] \
            || { echo "[build] ERROR: CalamityMod.tmod download invalid"; rm -f /preload/Mods/CalamityMod.tmod; exit 1; }; \
    else \
        echo "[build] CALAMITY_MOD_URL not set; CalamityMod will NOT be bundled" >&2; \
    fi && \
    if [ -n "$CALAMITY_MUSIC_URL" ]; then \
        echo "[build] fetching CalamityModMusic.tmod from $CALAMITY_MUSIC_URL..."; \
        curl -fL --retry 3 "$CALAMITY_MUSIC_URL" -o /preload/Mods/CalamityModMusic.tmod \
            && [ "$(head -c 4 /preload/Mods/CalamityModMusic.tmod)" = "TMOD" ] \
            || { echo "[build] ERROR: CalamityModMusic.tmod download invalid"; rm -f /preload/Mods/CalamityModMusic.tmod; exit 1; }; \
    else \
        echo "[build] CALAMITY_MUSIC_URL not set; CalamityModMusic will NOT be bundled" >&2; \
    fi

EXPOSE 7777

ENTRYPOINT [ "/home/tml/entrypoint-wrapper.sh" ]
