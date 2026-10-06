# syntax=docker/dockerfile:1
#
# webtop:alpine-sway  (China-network optimized rebuild)
#
# Wayland/Sway flavour. The upstream LinuxServer base image hard-codes labwc
# as its Wayland compositor (see /defaults/startwm_wayland.sh), so this image
# overrides that script to launch sway instead, while reusing the base image's
# entire selkies/xorg/nginx/s6 plumbing.
#
# Base: ghcr.io/linuxserver/baseimage-selkies:alpine324  ->  Alpine 3.24.1
#
# China optimization: apk repositories are rewritten to a domestic mirror
# before any package is installed.
#
FROM ghcr.io/linuxserver/baseimage-selkies:alpine324

# set version label
ARG BUILD_DATE
ARG VERSION
ARG SWAY_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="alpineopenbox-rebuild"

# title
# PIXELFLUX_WAYLAND=true switches the base image plumbing into Wayland mode
# (this is the variable the base image's s6 services actually test for);
# SELKIES_WAYLAND_SOCKET_INDEX=2 mirrors the upstream wayland flavours.
ENV TITLE="Alpine Sway" \
    PIXELFLUX_WAYLAND="true" \
    SELKIES_WAYLAND_SOCKET_INDEX="2"

# ---------------------------------------------------------------------------
# China mirror optimization.
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
    dbus \
    font-noto-cjk \
    foot \
    fuzzel \
    grim \
    libcap-setcap \
    mousepad \
    slurp \
    sway \
    swaybg \
    swayidle \
    swaylock \
    util-linux-misc \
    waybar \
    wl-clipboard \
    xwayland && \
  echo "**** application tweaks ****" && \
  ln -sf \
    /usr/bin/foot \
    /usr/bin/x-terminal-emulator && \
  sed -i \
    's:/usr/bin/chromium-browser:/usr/bin/chromium:g' \
    /usr/share/applications/chromium.desktop && \
  echo "**** drop capabilities from sway (required inside containers) ****" && \
  setcap -r \
    /usr/bin/sway 2>/dev/null || true && \
  echo "**** cleanup ****" && \
  rm -rf \
    /config/.cache \
    /tmp/*

# add local files (sway session script + sway config)
COPY /root /

# Seed the sway config into the abc user's home and enforce permissions.
# The chmod is required: the base image's svc-de service execs
# /defaults/startwm_wayland.sh directly, so it MUST be executable, otherwise
# the session crash-loops with "Permission denied". Do not rely on the
# build context preserving the exec bit.
RUN \
  echo "**** fix session script permissions ****" && \
  chmod 755 \
    /defaults/startwm_wayland.sh && \
  chmod 644 \
    /defaults/sway-config \
    /defaults/waybar-config && \
  echo "**** seed sway config for the abc user ****" && \
  mkdir -p \
    /config/.config/sway \
    /config/.config/waybar && \
  cp \
    /defaults/sway-config \
    /config/.config/sway/config && \
  cp \
    /defaults/waybar-config \
    /config/.config/waybar/config && \
  chown -R abc:abc \
    /config/.config

# ports and volumes
EXPOSE 3000

VOLUME /config
