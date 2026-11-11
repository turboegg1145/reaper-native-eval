# syntax=docker/dockerfile:1

# Native Linux REAPER evaluation sandbox.
# No Wine, no Python evaluation harness, no Lua helper library.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG REAPER_TARBALL=reaper785_linux_x86_64.tar.xz
ARG REAPER_SHA256=b962c40a51535d2faf9796f56270f9e331c9d424b5741472277d7bfd6c4893ac
ARG SURGE_VERSION=1.3.4
ARG SURGE_SHA256=a6e55064487f624147d515b9ae5fc79a568b69746675b2083abde628ca7bb151
ARG DRAGONFLY_VERSION=3.2.10
ARG DRAGONFLY_SHA256=59f1593120de82e31dd194e2ab1536af14fec2b3ec6ec45abf6d9c8ac02ef430

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/root \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    SURGE_DATA_HOME=/usr/share/surge-xt

# Runtime libraries for REAPER, Xvfb, ffmpeg, and the native plugins.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        xz-utils \
        xvfb \
        xauth \
        ffmpeg \
        libasound2t64 \
        libgtk-3-0t64 \
        libx11-6 \
        libxext6 \
        libxinerama1 \
        libxrandr2 \
        libxcursor1 \
        libxi6 \
        libxcb-cursor0 \
        libxcb-xkb1 \
        libxkbcommon-x11-0 \
        libfontconfig1 \
        libfreetype6 \
        libcairo2 \
        libpango-1.0-0 \
        libpangocairo-1.0-0 \
        libgl1 \
        libegl1 \
        xdg-utils \
        xclip \
        fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# Official Linux-native REAPER tarball. Pinned and checksum-verified.
RUN set -eux; \
    curl -fsSL --retry 3 \
        "https://www.reaper.fm/files/7.x/${REAPER_TARBALL}" \
        -o /tmp/reaper.tar.xz; \
    echo "${REAPER_SHA256}  /tmp/reaper.tar.xz" | sha256sum -c -; \
    mkdir -p /opt/reaper; \
    tar -xJf /tmp/reaper.tar.xz -C /tmp; \
    cp -a /tmp/reaper_linux_x86_64/REAPER/. /opt/reaper/; \
    ln -sf /opt/reaper/reaper /usr/local/bin/reaper; \
    rm -rf /tmp/reaper.tar.xz /tmp/reaper_linux_x86_64; \
    reaper -h >/dev/null 2>&1 || true

# Surge XT: native Linux VST3 + CLAP + factory content. Installed from the
# upstream .deb so its dependencies and data paths are registered correctly.
RUN set -eux; \
    curl -fsSL --retry 3 \
        "https://github.com/surge-synthesizer/releases-xt/releases/download/${SURGE_VERSION}/surge-xt-linux-x64-${SURGE_VERSION}.deb" \
        -o /tmp/surge-xt.deb; \
    echo "${SURGE_SHA256}  /tmp/surge-xt.deb" | sha256sum -c -; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/surge-xt.deb; \
    rm -f /tmp/surge-xt.deb; \
    rm -rf /var/lib/apt/lists/*

# Dragonfly Reverb: upstream native VST3 + CLAP binaries.
RUN set -eux; \
    curl -fsSL --retry 3 \
        "https://github.com/michaelwillis/dragonfly-reverb/releases/download/${DRAGONFLY_VERSION}/dragonfly-reverb-${DRAGONFLY_VERSION}-linux-x86_64.tar.xz" \
        -o /tmp/dragonfly.tar.xz; \
    echo "${DRAGONFLY_SHA256}  /tmp/dragonfly.tar.xz" | sha256sum -c -; \
    mkdir -p /tmp/dragonfly; \
    tar -xJf /tmp/dragonfly.tar.xz -C /tmp/dragonfly --strip-components=1; \
    install -d /usr/lib/vst3 /usr/lib/clap; \
    cp -a /tmp/dragonfly/*.vst3 /usr/lib/vst3/; \
    cp -a /tmp/dragonfly/*.clap /usr/lib/clap/; \
    rm -rf /tmp/dragonfly.tar.xz /tmp/dragonfly

# No physical audio device in the container. linux_audio_mode=3 selects the
# Dummy Audio backend; the other keys suppress startup/render dialogs.
COPY reaper.ini /root/.config/REAPER/reaper.ini

COPY bootstrap_scan.lua runner_wrapper.lua test_song.lua /opt/scripts/
RUN chmod 0755 /opt/scripts/*.lua && mkdir -p /workspace

# Build-time plugin-cache warm-up. The scan cache is written into this image
# layer, so normal container starts do not rescan Surge XT or Dragonfly.
RUN set -eux; \
    xvfb-run -a reaper -nosplash -ignoreerrors -new /opt/scripts/bootstrap_scan.lua; \
    test -s /root/.config/REAPER/reaper-vstplugins64.ini; \
    grep -q 'Surge XT' /root/.config/REAPER/reaper-vstplugins64.ini; \
    grep -q 'Dragonfly Hall Reverb' /root/.config/REAPER/reaper-vstplugins64.ini; \
    test -s /root/.config/REAPER/reaper-clap-linux-x86_64.ini; \
    grep -q 'Surge XT' /root/.config/REAPER/reaper-clap-linux-x86_64.ini; \
    grep -q 'Dragonfly Hall Reverb' /root/.config/REAPER/reaper-clap-linux-x86_64.ini

WORKDIR /workspace

# The only runtime entrypoint: Xvfb + native headless REAPER + wrapper script.
CMD ["xvfb-run", "-a", "reaper", "-nosplash", "-ignoreerrors", "-new", "/opt/scripts/runner_wrapper.lua"]
