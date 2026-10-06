# syntax=docker/dockerfile:1
#
# webtop:alpine-openbox-novnc
#
# A from-scratch Alpine + Openbox desktop served over VNC/noVNC, deliberately
# kept minimal: chromium + openbox + wine, plus only what the session needs to
# run.
#
# IMAGE VARIANTS
# --------------
#   v1 (legacy/Dockerfile.v1-dockercli): shipped docker-cli so the desktop
#       could drive the host's Docker socket.
#   v2: docker-cli REMOVED, wine ADDED. The image no longer mounts
#       /var/run/docker.sock (see docker-compose.yml) and instead runs Windows
#       software through Wine. The openbox look is copied from
#       linuxserver/webtop:alpine-openbox (Artwiz-boxed theme, NLMC title
#       layout, Noto Sans) -- see the styling step near the end of this file.
#   v3 (this file): the tint2 top panel is GONE, and Xvfb + x11vnc have been
#       replaced by a single TigerVNC Xvnc, which is what makes the desktop
#       resolution adaptive (it honours the viewer's SetDesktopSize request;
#       x11vnc discarded it). See the RESOLUTION section below.
#
# WHY THIS EXISTS
# ---------------
# The previous build reused LinuxServer's baseimage-selkies. That base image is
# built around selkies/pixelflux, which made the stack hard to reason about and
# tied us to a moving, sometimes-broken upstream. This image drops that
# dependency entirely:
#
#   Xvnc (X server + VNC server in one process)
#     |
#     +-- openbox            the window manager (no panel: see below)
#     |
#     +-- websockify + noVNC (browser)
#
# Everything comes from the official Alpine repositories, so a rebuild only
# ever tracks Alpine itself.
#
# RESOLUTION IS ADAPTIVE (v3)
# ---------------------------
# noVNC's "resize=remote" mode sends the viewer's viewport size to the server as
# an RFB SetDesktopSize message. Measured against both servers with
# scripts/vncresize.py:
#
#   x11vnc 0.9.17   before=1280x800  sent 1600x900  after=(1280, 800)  discarded
#   Xvnc 1.15       before=1280x800  sent 1600x900  after=(1600, 900)  resized
#
# So the Xvfb+x11vnc pair could never do this, and Xvnc can. VNC_RESOLUTION is
# now only the size the desktop starts at (and the floor it can shrink to);
# once a browser connects, the desktop follows the browser window, and openbox
# reflows the windows to match. The noVNC default is switched from 'off' to
# 'remote' in the same install step below, and the build asserts the patch.
#
# NO PANEL (v3)
# -------------
# tint2 is not installed any more: the top bar (clock + window buttons) is gone
# by request. That also removes the tint2 segfault-on-Wine-churn problem this
# image used to work around -- see README for the (now historical) write-up.
# Window switching is openbox's own: Alt-Tab, or middle-click on the desktop
# for the client list.
#
# SIZE OPTIMISATION (see the combined install+prune step below)
# -------------------------------------------------------------
# apk resolves dependencies whether or not they are used at runtime, so the
# dependency trees drag in weight this image never executes:
#
#   * gallium-pipe (~90 MB): one .so per GPU (iris, crocus, radeonsi, nouveau,
#     i915, r300, r600, vmwgfx). A container has no GPU; only pipe_swrast.so
#     (the software rasteriser) is kept.  -> REMOVED
#
#   * websockify -> py3-numpy -> openblas (~73 MB). websockify imports numpy
#     inside a try/except ImportError and merely warns "HyBi protocol will be
#     slower" without it.                                              -> REMOVED
#
#   * tigervnc -> perl (~36 MB). Only the vncserver wrapper script is perl; the
#     Xvnc binary we actually run is C++. Verified by running the session after
#     the prune.                                                       -> REMOVED
#
#   * libLLVM.so.20 (170 MB) + libgallium (40 MB): these look like the same
#     kind of dead GPU weight, but they are LOAD-BEARING. Xvfb links
#     libGL.so.1 -> libgallium -> libLLVM. Removing them makes Xvfb refuse to
#     start ("Error loading shared library libgallium-...: needed by
#     libGL.so.1"), which kills the whole session.                    -> KEPT
#
# Pruning must happen INSIDE the same RUN as the install, otherwise Docker
# keeps the original files in the earlier layer and the image does not shrink.
#
# WINE (added in v2)
# ------------------
# wine 10.7 comes from Alpine's community repository and unpacks to ~372 MB:
#
#   /usr/lib/wine/x86_64-windows   182 MB   the 64-bit PE builtins
#   /usr/lib/wine/i386-windows     185 MB   the 32-bit PE builtins
#   /usr/lib/wine/x86_64-unix      5.5 MB   the Unix-side driver .so files
#
#   * The i386 tree is why 32-bit Windows software works here without multilib:
#     Wine's "new WoW64" runs 32-bit PE code on the 64-bit host. It is 185 MB
#     and it is the single most useful half of the package, so it stays.
#
#   * Wine pulls in mesa-gl for libGL. That is NOT extra weight: Xvfb already
#     needs libGL -> libgallium -> libLLVM (see above), so those libraries were
#     in the image before Wine arrived. The gallium-pipe prune below still
#     applies, so Wine does not reintroduce the per-GPU drivers.
#
#   * Wine's Unix modules link the media/scan/PCSC/pcap stacks:
#       winegstreamer.so -> gstreamer + gst-plugins-base
#       gphoto2.so       -> libgphoto2
#       sane.so          -> sane
#       winscard.so      -> pcsc-lite-libs
#       wpcap.so         -> libpcap
#     Together they are under 10 MB, and each is the only consumer of its
#     library, so they are kept: deleting them would silently remove DirectShow
#     media playback, scanner/camera passthrough and smartcard support to save
#     almost nothing.
#
#   * Wine has no package for wine-mono or wine-gecko on Alpine. WINEDLLOVERRIDES
#     disables mscoree/mshtml (see the ENV block) so a Windows app that wants
#     .NET/IE fails fast instead of blocking the desktop behind a download
#     dialog that cannot complete.
#
#   * Wine enumerates system fonts through fontconfig (win32u.so dlopens it), so
#     the image's font-noto-cjk also covers Chinese text inside Windows apps.
#
# China-network optimisation:
#   apk repositories are rewritten to a domestic mirror before the first
#   package operation.
#
FROM alpine:latest

ARG BUILD_DATE
ARG VERSION
ARG APK_MIRROR=mirror.nju.edu.cn

LABEL build_version="webtop-novnc version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="alpineopenbox-rebuild"
LABEL org.opencontainers.image.title="webtop-alpine-openbox-novnc"

# ---------------------------------------------------------------------------
# China mirror + upgrade to the current Alpine release.
#
# The base is `alpine:latest` -- the newest stable release -- so a rebuild
# tracks Alpine instead of pinning a branch (the old linuxserver image was
# stuck on 3.21 for 14 months). The sed below only swaps the CDN host for a
# domestic mirror; the v3.xx path comes from whatever the base image ships, so
# both stay in step. `apk upgrade` then picks up the latest point release.
# ---------------------------------------------------------------------------
RUN \
  echo "**** configure alpine mirror: ${APK_MIRROR} ****" && \
  sed -i \
    "s|dl-cdn.alpinelinux.org|${APK_MIRROR}|g" \
    /etc/apk/repositories && \
  cat /etc/apk/repositories && \
  echo "**** upgrade base ****" && \
  apk upgrade --no-cache

# NOTE: TITLE must stay a SINGLE token. It is passed to Xvnc as -desktop, and
# supervisord expands %(ENV_x)s before splitting the command on whitespace, so a
# value with a space ("Alpine Openbox") turns into a stray argument:
#     Xvnc: Unrecognized option: Openbox   -> the whole session fails to start
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DISPLAY=:1 \
    HOME=/config \
    TITLE=webtop \
    VNC_PORT=5901 \
    NOVNC_PORT=3000 \
    VNC_RESOLUTION=1280x800 \
    VNC_DEPTH=24 \
    WINEPREFIX=/config/.wine \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES="mscoree,mshtml="

# ---------------------------------------------------------------------------
# Packages + prune, in ONE RUN.
#
# The prune MUST live in the same layer as the install. Deleting files in a
# later RUN does not shrink the image: Docker keeps the earlier layer intact and
# the deletion only records a whiteout on top. Doing it here is what actually
# reclaims the space.
#
# Packages, grouped by why they are here:
#   core      : chromium, openbox, wine
#   session   : tigervnc (Xvnc), novnc, websockify, supervisor, dbus(+x11)
#   tools     : st, mousepad, xterm, xdg-utils, setxkbmap
#   fonts/i18n: font-noto (Latin UI font, matches the LinuxServer look),
#               font-noto-cjk (Chinese), font-dejavu, adwaita-icon-theme
#
# NOTE: docker-cli is deliberately NOT installed any more. The desktop cannot
# talk to the host Docker socket; use the host shell for that.
#
# PRUNE NOTES
# -----------
# Removed:
#   * gallium-pipe hardware drivers. This directory holds one .so per GPU
#     (iris, crocus, radeonsi, nouveau, i915, r300, r600, vmwgfx) totalling
#     ~90 MB. A container has no GPU, so only pipe_swrast.so (the software
#     rasteriser Xvfb falls back to) is kept.
#   * numpy + openblas (~73 MB). websockify imports numpy inside a
#     try/except ImportError and just warns "HyBi protocol will be slower"
#     without it.
#
# Deliberately NOT removed (these look like dead weight but are load-bearing):
#   * libLLVM.so.20 (170 MB) and libgallium (40 MB). Xvfb links libGL.so.1,
#     which requires libgallium, which requires libLLVM. Removing them stops
#     Xvfb from starting:
#       "Error loading shared library libgallium-...: needed by libGL.so.1"
#     This was tried; it appeared to work because Xvfb was already running.
#     It only fails on the NEXT container start -- so always re-test in a NEW
#     container rather than mutating a live one.
# ---------------------------------------------------------------------------
RUN \
  echo "**** install packages ****" && \
  apk add --no-cache \
    adwaita-icon-theme \
    bash \
    breeze-cursors \
    chromium \
    dbus \
    dbus-x11 \
    font-dejavu \
    font-noto \
    font-noto-cjk \
    libcap-setcap \
    mousepad \
    novnc \
    openbox \
    py3-xdg \
    setxkbmap \
    st \
    supervisor \
    tigervnc \
    util-linux-misc \
    websockify \
    wine \
    xdg-utils \
    xkeyboard-config \
    xterm && \
  echo "**** application tweaks ****" && \
  ln -sf /usr/bin/st /usr/bin/x-terminal-emulator && \
  echo "**** prune unused GPU drivers (keep the software rasteriser) ****" && \
  find /usr/lib/gallium-pipe -type f ! -name 'pipe_swrast.so' -delete 2>/dev/null || true && \
  echo "**** prune CJK serif fonts (Sans covers every UI/page case) ****" && \
  rm -f /usr/share/fonts/noto/NotoSerifCJK-*.ttc && \
  echo "**** prune numpy/openblas (websockify treats numpy as optional) ****" && \
  rm -rf \
    /usr/lib/python3.*/site-packages/numpy* \
    /usr/lib/libopenblas*.so && \
  echo "**** prune perl (only tigervnc's vncserver helper wants it; Xvnc is C++) ****" && \
  rm -rf \
    /usr/bin/perl* \
    /usr/lib/perl5 \
    /usr/share/perl5 && \
  echo "**** prune docs and caches ****" && \
  rm -rf \
    /var/cache/apk/* \
    /tmp/* \
    /usr/share/doc \
    /usr/share/man && \
  echo "**** default noVNC to remote (adaptive) resize ****" && \
  sed -i "s|UI.initSetting('resize', 'off')|UI.initSetting('resize', 'remote')|" \
    /usr/share/novnc/app/ui.js && \
  { grep -q "UI.initSetting('resize', 'remote')" /usr/share/novnc/app/ui.js || \
    { echo "FATAL: noVNC resize default patch did not apply (upstream changed)" >&2; exit 1; }; } && \
  echo "**** make the adaptive resize stick (webtop-adaptive.js) ****" && \
  sed -i "s|<script type=\"module\" crossorigin=\"anonymous\" src=\"app/error-handler.js\"></script>|&\n    <script type=\"module\" src=\"app/webtop-adaptive.js\"></script>|" \
    /usr/share/novnc/vnc.html && \
  { grep -q "app/webtop-adaptive.js" /usr/share/novnc/vnc.html || \
    { echo "FATAL: webtop-adaptive.js is not wired into vnc.html (upstream changed)" >&2; exit 1; }; } && \
  echo "**** rebuild font cache after pruning ****" && \
  fc-cache -f > /dev/null 2>&1 || true && \
  echo "**** resulting size ****" && \
  du -sh /usr/lib /usr/share 2>/dev/null

RUN \
  echo "**** create abc user ****" && \
  addgroup -g 1000 abc && \
  adduser -u 1000 -G abc -s /bin/bash -D abc && \
  mkdir -p /config /defaults && \
  chown -R abc:abc /config

# local files: supervisor programs, init script, openbox defaults, wine helpers
COPY /root /

# ---------------------------------------------------------------------------
# LinuxServer.io openbox appearance (copied from linuxserver/webtop:alpine-openbox)
#
# Diffed that image's /config/.config/openbox/rc.xml (790 lines, container
# `webtop1`) against Alpine's stock /etc/xdg/openbox/rc.xml: once whitespace and
# line wrapping are ignored there are exactly THREE semantic differences, and
# the menu delays, mousebinds (including Root Right-click -> root-menu), focus /
# placement / dragThreshold and all six theme fonts (sans 8 bold titles, 9
# normal menus) are identical:
#
#   theme        Clearlooks  -> Artwiz-boxed   (ships inside Alpine's openbox
#                                               package as a text themerc, so
#                                               nothing needs to be copied)
#   titleLayout  NLIMC       -> NLMC           (no minimise button)
#   keybind      + C-S-d     -> ToggleDecorations
#
# scripts/verify.sh checks the result; the script itself asserts every value it
# changes, so a future Alpine that renames its default theme fails the build
# instead of silently shipping a half-styled image.
#
# The styled file is installed twice: as the system default (used when the user
# has no rc.xml of their own) and as /defaults/rc.xml, which 10-setup copies
# into the user's config on first run. font-noto is installed for the same
# reason the LinuxServer image has it -- their rc.xml asks for the font family
# "sans", and without Noto that resolves to DejaVu here, so the window titles
# would not actually look the same.
# ---------------------------------------------------------------------------
RUN \
  echo "**** apply LinuxServer.io openbox style ****" && \
  chmod 755 /usr/local/bin/openbox-lsio-style && \
  /usr/local/bin/openbox-lsio-style /etc/xdg/openbox/rc.xml && \
  cp /etc/xdg/openbox/rc.xml /defaults/rc.xml && \
  echo "**** validate the styled rc.xml ****" && \
  python3 -c "\
import xml.etree.ElementTree as ET; \
n='{http://openbox.org/3.4/rc}'; \
r=ET.parse('/defaults/rc.xml').getroot(); \
theme=r.find(n+'theme/'+n+'name').text; \
layout=r.find(n+'theme/'+n+'titleLayout').text; \
binds=r.findall(n+'keyboard/'+n+'keybind'); \
assert theme=='Artwiz-boxed', theme; \
assert layout=='NLMC', layout; \
print('rc.xml: theme=%s titleLayout=%s keybinds=%d' % (theme, layout, len(binds)))"

RUN \
  echo "**** fix permissions ****" && \
  chmod 755 \
    /etc/cont-init.d/10-setup \
    /usr/bin/start-desktop \
    /usr/bin/chromium-webtop \
    /usr/bin/wine-webtop \
    /usr/bin/wine-prefix-init && \
  chmod 644 /etc/supervisor.d/*.ini && \
  chmod 644 /defaults/* && \
  chmod 644 /usr/share/novnc/app/webtop-adaptive.js && \
  echo "**** the adaptive-resize script must be present (it arrives with COPY /root) ****" && \
  test -s /usr/share/novnc/app/webtop-adaptive.js && \
  grep -q "app/webtop-adaptive.js" /usr/share/novnc/vnc.html && \
  chmod 644 \
    /usr/share/applications/wine-webtop.desktop \
    /etc/xdg/mimeapps.list && \
  ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

EXPOSE 3000

VOLUME /config

ENTRYPOINT ["/usr/bin/start-desktop"]
