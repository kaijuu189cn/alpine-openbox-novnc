#!/usr/bin/env bash
#
# Wayland session launcher for webtop:alpine-sway
#
# Overrides /defaults/startwm_wayland.sh from
# ghcr.io/linuxserver/baseimage-selkies, which launches labwc.
#
# Session flow in the base image:
#   1. svc-selkies starts selkies/pixelflux, which OWNS the Wayland display and
#      creates the socket at ${XDG_RUNTIME_DIR}/wayland-1.
#   2. svc-de waits for that socket, then execs this script as user `abc`.
#   3. This script starts the compositor, which renders INTO the selkies
#      Wayland display.
#
# Therefore sway must run as a *nested* Wayland client of the selkies socket.
# It must NOT create its own headless/drm backend, and must not clobber
# WAYLAND_DISPLAY - we deliberately inherit it from the base image.
#
ulimit -c 0

export XCURSOR_THEME=breeze_cursors
export XCURSOR_SIZE=24
export XKB_DEFAULT_LAYOUT=us
export XKB_DEFAULT_RULES=evdev

# XDG_RUNTIME_DIR must exist and be private; the base image points it at $HOME/.XDG.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$HOME/.XDG}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Do NOT override WAYLAND_DISPLAY - inherit the selkies-owned socket.
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

# sway nests inside the selkies display; there is no DRM device to drive.
export WLR_BACKENDS=wayland
export WLR_RENDERER_ALLOW_SOFTWARE=1
export LIBGL_ALWAYS_SOFTWARE=1
export WLR_LIBINPUT_NO_DEVICES=1

# Xwayland for chromium and other X11 clients.
export DISPLAY=:0
export MOZ_ENABLE_WAYLAND=1

# ---------------------------------------------------------------------------
# Make sure a sway config exists BEFORE sway parses it.
#
# svc-de launches this script as soon as the selkies Wayland socket appears,
# which can be before the config has been seeded into $HOME. sway pops a
# "There are errors in your config file" swaynag when it cannot read one, so
# seed it here defensively from /defaults.
# ---------------------------------------------------------------------------
SWAY_DIR="$HOME/.config/sway"
SWAY_CONF="$SWAY_DIR/config"
if [ ! -s "$SWAY_CONF" ]; then
  mkdir -p "$SWAY_DIR"
  if [ -s /defaults/sway-config ]; then
    cp /defaults/sway-config "$SWAY_CONF"
  fi
fi

# Same for waybar, otherwise waybar aborts on a missing config.
WAYBAR_DIR="$HOME/.config/waybar"
if [ ! -s "$WAYBAR_DIR/config" ] && [ -s /defaults/waybar-config ]; then
  mkdir -p "$WAYBAR_DIR"
  cp /defaults/waybar-config "$WAYBAR_DIR/config"
fi

# ---------------------------------------------------------------------------
# Start a persistent D-Bus session bus.
#
# `dbus-launch --exit-with-session sway` is fragile here: sway is a NESTED
# compositor that selkies may restart, and when the launching session ends
# dbus-launch tears the bus down (leaving a stale DBUS_SESSION_BUS_ADDRESS).
# waybar then dies with "Error spawning command line dbus-launch --autolaunch".
# Starting dbus-daemon directly keeps the bus alive for the whole container.
# ---------------------------------------------------------------------------
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] || ! dbus-send --session --dest=org.freedesktop.DBus \
      --type=method_call --print-reply /org/freedesktop/DBus \
      org.freedesktop.DBus.ListNames > /dev/null 2>&1; then
  if command -v dbus-launch > /dev/null 2>&1; then
    eval "$(dbus-launch --sh-syntax)"
    export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
  fi
fi

# Launch sway. Keep stderr out of the login console but preserve it for
# debugging via /config/sway-session.log.
exec /usr/bin/sway > /config/sway-session.log 2>&1
