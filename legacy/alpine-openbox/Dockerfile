# syntax=docker/dockerfile:1
#
# webtop:alpine-openbox  (China-network optimized rebuild)
#
# Rebuilt from scratch because linuxserver/webtop:alpine-openbox stopped
# updating (last build 2025-06-24, Alpine 3.21.3).
#
# This build tracks the current upstream base image family:
#   ghcr.io/linuxserver/baseimage-selkies:alpine324  ->  Alpine 3.24.1
#
# China optimization:
#   * apk repositories rewritten to mirror.nju.edu.cn (fastest of the
#     mirrors benchmarked from this network)
#   * MIRROR_ARG lets you switch mirrors at build time without editing
#
FROM ghcr.io/linuxserver/baseimage-selkies:alpine324

# set version label
ARG BUILD_DATE
ARG VERSION
ARG OPENBOX_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="alpineopenbox-rebuild"

# title
ENV TITLE="Alpine Openbox"

# ---------------------------------------------------------------------------
# China mirror optimization.
# Rewrite the Alpine repositories before any package operation so every apk
# call in this build (and any later `apk add` inside the container) is served
# from a domestic mirror.
# ---------------------------------------------------------------------------
ARG APK_MIRROR=mirror.nju.edu.cn
RUN \
  echo "**** configure alpine mirror: ${APK_MIRROR} ****" && \
  sed -i \
    "s|dl-cdn.alpinelinux.org|${APK_MIRROR}|g" \
    /etc/apk/repositories && \
  cat /etc/apk/repositories

RUN \
  echo "**** install packages ****" && \
  apk add --no-cache \
    adwaita-icon-theme \
    breeze-cursors \
    chromium \
    font-noto-cjk \
    libcap-setcap \
    mousepad \
    st \
    tint2 \
    util-linux-misc \
    xterm && \
  echo "**** application tweaks ****" && \
  ln -sf \
    /usr/bin/st \
    /usr/bin/x-terminal-emulator && \
  sed -i \
    's:/usr/bin/chromium-browser:/usr/bin/chromium:g' \
    /usr/share/applications/chromium.desktop && \
  echo "**** cleanup ****" && \
  rm -rf \
    /config/.cache \
    /tmp/*

# add local files (openbox rc.xml / menu / autostart overrides)
COPY /root /

# Normalise permissions on the overlay files. The base image's services read
# these directly, and the build context must not be trusted to carry sane modes.
RUN \
  echo "**** fix overlay permissions ****" && \
  chmod 644 \
    /defaults/menu.xml \
    /defaults/autostart 2>/dev/null || true

# ports and volumes
EXPOSE 3000

VOLUME /config
