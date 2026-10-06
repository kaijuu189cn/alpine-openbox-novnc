#!/usr/bin/env bash
#
# verify.sh -- start the webtop noVNC image and prove it actually works.
#
# Checks performed:
#   1. container stays up and all supervised services (xvnc, openbox, novnc)
#      are RUNNING
#   2. the VNC server completes an RFB handshake
#   3. the framebuffer starts at the configured size
#   4. noVNC answers over HTTP, and the adaptive-resize override is served,
#      referenced by vnc.html, applied in a real browser, and overridable
#      from the URL
#   5. REGRESSION: Chromium launched via the Openbox menu command really opens
#      a browser window (this is the "webbrowser 打不开" bug)
#   6. ADAPTIVE RESOLUTION: with that window on screen, the server honours a
#      SetDesktopSize request, the framebuffer takes the new size and the window
#      repaints (this is what noVNC's resize=remote does). An idle panel-less
#      desktop is black by design, so pixels are only asserted with a window up.
#   8. REGRESSION: Wine builds a prefix, runs 64-bit AND 32-bit (WoW64) Windows
#      programs, sees the system fonts, and `wine-webtop notepad` maps a window
#
# Also asserted along the way:
#   * v3 image contract: docker cli ABSENT, wine helpers present, and NO panel
#     (tint2 is not installed)
#   * the Openbox menu file parses (a double hyphen in its XML comment used to
#     make libxml2 reject it, leaving the root menu empty)
#   * the LinuxServer.io openbox look is in place: Artwiz-boxed theme, NLMC
#     title layout, C-S-d keybind, and "sans" resolving to Noto Sans
#
# NOTE ON PORTS: the image serves noVNC on 3000. If you run this from inside
# another container that only shares the Docker socket, the published port is
# reachable on the HOST, not your own 127.0.0.1. Override PROBE_HOST with the
# host address (e.g. the default gateway) in that case.
#
# USAGE
#   ./scripts/verify.sh
#   PROBE_HOST=192.168.1.5 ./scripts/verify.sh
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_HOST="${PROBE_HOST:-127.0.0.1}"
PORT="${PORT:-3140}"
IMAGE="${IMAGE:-webtop:alpine-openbox-novnc}"
NAME="${NAME:-wt-verify-novnc}"

pass=0; fail=0
ok()  { echo "   [ OK ] $*"; pass=$((pass+1)); }
bad() { echo "   [FAIL] $*"; fail=$((fail+1)); }

echo "=============================================="
echo " verifying ${IMAGE}"
echo "   probe host : ${PROBE_HOST}:${PORT}"
echo "=============================================="

docker rm -f "$NAME" > /dev/null 2>&1 || true
docker volume rm "${NAME}-vol" > /dev/null 2>&1 || true

docker run -d --name "$NAME" -v "${NAME}-vol:/config" \
  -p "${PORT}:3000" "$IMAGE" > /dev/null 2>&1

echo "   waiting 35s for the session to come up..."
sleep 35

# --- 1. container + services --------------------------------------------
if [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = "true" ]; then
  ok "container is running"
else
  bad "container is not running"
  docker logs "$NAME" 2>&1 | tail -20
  exit 1
fi

SERVICES="$(docker exec "$NAME" sh -c 'supervisorctl status 2>/dev/null' | grep -vE 'UserWarning|pkg_resources')"

# A single sample can catch a process mid-restart, so retry before declaring a
# service broken.
svc_running() {
  local svc="$1" i
  for i in 1 2 3 4; do
    docker exec "$NAME" sh -c "supervisorctl status $svc 2>/dev/null" | grep -q "RUNNING" && return 0
    sleep 3
  done
  return 1
}

for svc in xvnc openbox novnc; do
  if svc_running "$svc"; then
    ok "service '${svc}' is RUNNING"
  else
    bad "service '${svc}' is not RUNNING"
    docker exec "$NAME" sh -c 'supervisorctl status 2>/dev/null' | grep -vE 'UserWarning|pkg_resources' | sed 's/^/          /'
  fi
done

# --- 1b. core tools the image promises to ship ---------------------------
echo "$SERVICES" > /dev/null   # keep shellcheck quiet about the reuse above
for tool in chromium openbox wine; do
  if docker exec "$NAME" sh -c "command -v $tool" > /dev/null 2>&1; then
    ok "core tool '${tool}' is present"
  else
    bad "core tool '${tool}' is MISSING"
  fi
done

# --- 1c. image contract: docker cli gone, wine helpers installed ---------
if docker exec "$NAME" sh -c 'command -v docker' > /dev/null 2>&1; then
  bad "docker cli is installed (v2 removed it)"
else
  ok "docker cli is absent (removed in v2)"
fi
for tool in wine-webtop wine-prefix-init; do
  if docker exec "$NAME" sh -c "command -v $tool" > /dev/null 2>&1; then
    ok "wine helper '${tool}' is present"
  else
    bad "wine helper '${tool}' is MISSING"
  fi
done

# --- 1d. REGRESSION: the Openbox menu file must actually parse -----------
# It used to contain a double hyphen inside an XML comment; libxml2 rejects the
# whole file for that, so Openbox silently fell back to an empty root menu.
MENU_ERR="$(docker exec "$NAME" sh -c 'c=$(grep -ci "parser error" /var/log/supervisor/openbox.log 2>/dev/null); echo "${c:-0}"' | tr -d '[:space:]')"
if [ "${MENU_ERR:-1}" = "0" ]; then
  ok "Openbox menu.xml parses (no libxml2 parser errors)"
else
  bad "Openbox reported ${MENU_ERR} menu parser error(s); the root menu is empty"
fi

# --- 1e. LinuxServer.io openbox style --------------------------------
# The look is copied from linuxserver/webtop:alpine-openbox: theme
# Artwiz-boxed, title layout NLMC, and the font family the rc.xml asks for
# ("sans") must actually resolve to Noto Sans as it does there -- without
# font-noto it silently falls back to DejaVu and the titles look different.
if docker exec "$NAME" sh -c 'grep -q "<name>Artwiz-boxed</name>" /config/.config/openbox/rc.xml' > /dev/null 2>&1; then
  ok "openbox theme is Artwiz-boxed (LinuxServer style)"
else
  bad "openbox theme is not Artwiz-boxed in the user rc.xml"
fi
if docker exec "$NAME" sh -c 'grep -q "<titleLayout>NLMC</titleLayout>" /config/.config/openbox/rc.xml' > /dev/null 2>&1; then
  ok "openbox titleLayout is NLMC (as in the LinuxServer image)"
else
  bad "openbox titleLayout is not NLMC"
fi
if docker exec "$NAME" sh -c 'test -f /usr/share/themes/Artwiz-boxed/openbox-3/themerc' > /dev/null 2>&1; then
  ok "Artwiz-boxed themerc is installed"
else
  bad "Artwiz-boxed themerc is MISSING (no window decorations)"
fi
SANS="$(docker exec "$NAME" fc-match sans 2>/dev/null | head -1)"
if echo "$SANS" | grep -q "NotoSans"; then
  ok "'sans' resolves to Noto Sans (${SANS%:*})"
else
  bad "'sans' resolves to '${SANS:-nothing}', not Noto Sans"
fi
if docker exec "$NAME" sh -c 'grep -q "key=\"C-S-d\"" /config/.config/openbox/rc.xml' > /dev/null 2>&1; then
  ok "C-S-d keybind present (LinuxServer's only extra binding)"
else
  bad "C-S-d keybind missing from rc.xml"
fi

# --- 1f. v3 contract: there is no panel --------------------------------
# The tint2 top bar was removed on request. Everything that used to be
# supervised about it (crash counting, pid stability, BadDrawable storms) went
# with it -- and so did the Wine-churn segfault it needed working around.
if docker exec "$NAME" sh -c 'command -v tint2' > /dev/null 2>&1; then
  bad "tint2 is still installed (v3 removed the top panel)"
else
  ok "no panel: tint2 is not installed"
fi
if docker exec "$NAME" sh -c 'test -f /etc/supervisor.d/tint2.ini' > /dev/null 2>&1; then
  bad "a tint2 supervisor entry is still present"
else
  ok "no tint2 supervisor entry"
fi

# --- 2/3. VNC handshake and framebuffer size -----------------------------
docker cp "$HERE/vncprobe.py" "$NAME:/tmp/vncprobe.py" > /dev/null 2>&1
VNC_OUT="$(docker exec "$NAME" python3 /tmp/vncprobe.py 2>&1)"

if echo "$VNC_OUT" | grep -q "RFB 003"; then
  ok "VNC server completed an RFB handshake"
else
  bad "VNC handshake failed"
  echo "$VNC_OUT" | sed 's/^/          /'
fi

FB="$(echo "$VNC_OUT" | grep -oE 'framebuffer=[0-9]+x[0-9]+' | head -1)"
if [ -n "$FB" ]; then
  ok "framebuffer reports ${FB#framebuffer=}"
else
  bad "could not read framebuffer size"
fi

# NOTE: no colour assertion here. The desktop has no panel any more, so an idle
# session is a black root window plus the cursor (2 unique colours) -- by
# design, not a fault. Real rendering is asserted below, once a window exists
# (section 6b after Chromium opens, and section 8 at the end).
COLORS="$(echo "$VNC_OUT" | grep -oE 'unique_colors=[0-9]+' | head -1)"
echo "   [info] idle desktop framebuffer has ${COLORS#unique_colors=} unique colours (panel-less: expect ~2)"

# --- 5. noVNC over HTTP --------------------------------------------------
CODE="$(curl -s -o /tmp/_wt_verify.html -m 20 -w '%{http_code}' "http://${PROBE_HOST}:${PORT}/" 2>/dev/null)"
if [ "$CODE" = "200" ]; then
  ok "noVNC responds HTTP 200"
  if grep -qi "novnc" /tmp/_wt_verify.html; then
    ok "served page is the noVNC UI"
  else
    bad "served page does not look like noVNC"
  fi
else
  bad "noVNC returned '${CODE}' (probe ${PROBE_HOST}:${PORT})"
fi

# --- 5b. the adaptive-resize override must run in a real browser --------
# noVNC lets a value saved in the browser's localStorage win over the image's
# default, which is what used to stop the automatic resize. app/webtop-adaptive.js
# is loaded before noVNC initialises and stores resize=remote, then reports what
# it did on <html data-webtop-resize="...">. Checking that attribute in a real
# browser's DOM is the end-to-end proof that the override ran.
ADAPT_JS="$(curl -s -m 20 "http://${PROBE_HOST}:${PORT}/app/webtop-adaptive.js" 2>/dev/null)"
if echo "$ADAPT_JS" | grep -q "webtop-adaptive"; then
  ok "the adaptive-resize script is served by noVNC"
else
  bad "app/webtop-adaptive.js is not served (or is not our script)"
fi
if docker exec "$NAME" sh -c 'grep -q "app/webtop-adaptive.js" /usr/share/novnc/vnc.html'; then
  ok "vnc.html loads the adaptive-resize script"
else
  bad "vnc.html does not reference app/webtop-adaptive.js"
fi
ADAPT_DOM="$(docker exec "$NAME" su -s /bin/sh abc -c 'HOME=/tmp/domcheck XDG_RUNTIME_DIR=/tmp/domcheck chromium --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=/tmp/domcheck --virtual-time-budget=8000 --dump-dom http://127.0.0.1:3000/ 2>/dev/null | grep -c "data-webtop-resize=\"remote\""' 2>/dev/null | tr -d '[:space:]')"
if [ "${ADAPT_DOM:-0}" -ge 1 ] 2>/dev/null; then
  ok "a real browser applied the override (data-webtop-resize=remote)"
else
  bad "the adaptive-resize override did not run in the browser (headless Chromium DOM)"
fi
# ...and an explicit URL parameter must still win over the override.
ADAPT_URL="$(docker exec "$NAME" su -s /bin/sh abc -c 'HOME=/tmp/domcheck2 XDG_RUNTIME_DIR=/tmp/domcheck2 chromium --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=/tmp/domcheck2 --virtual-time-budget=8000 --dump-dom "http://127.0.0.1:3000/?resize=off" 2>/dev/null | grep -c "data-webtop-resize=\"off\""' 2>/dev/null | tr -d '[:space:]')"
if [ "${ADAPT_URL:-0}" -ge 1 ] 2>/dev/null; then
  ok "?resize=off still overrides the default (escape hatch works)"
else
  bad "the ?resize=off URL parameter was not honoured"
fi

# --- 6. REGRESSION: Chromium opens from the menu command -----------------
# Run from a script file rather than an inline string: the nested quoting of the
# su command inside `docker exec -d bash -c '...'` silently mangles and the
# script never executes.
# The helper uses setsid so Chromium survives the exec session teardown --
# without that it is killed before it can map a window, producing a false
# failure that looks exactly like the original bug.
docker cp "$HERE/chromium-regression.sh" "$NAME:/tmp/chromium-regression.sh" > /dev/null 2>&1
docker exec "$NAME" chmod 755 /tmp/chromium-regression.sh > /dev/null 2>&1
docker exec "$NAME" rm -f /config/chromium-regression.txt > /dev/null 2>&1
docker exec -d "$NAME" /tmp/chromium-regression.sh

echo "   waiting 40s for Chromium to map a window..."
sleep 40
CHROME_OUT="$(docker exec "$NAME" cat /config/chromium-regression.txt 2>/dev/null)"

if echo "$CHROME_OUT" | grep -qi "chromium"; then
  ok "Chromium opens a real window via the menu launcher"
  echo "$CHROME_OUT" | grep -i chromium | head -2 | sed 's/^/          /'
else
  bad "Chromium did NOT open a window (bug1 regression)"
  echo "$CHROME_OUT" | sed 's/^/          /' | head -4
fi

# --- 6b. ADAPTIVE RESOLUTION: resize with a window on screen ------------
# This is the mechanism noVNC's resize=remote uses to follow the browser
# window. x11vnc (v2) silently discarded it; Xvnc (v3) applies it. 1500x850 is
# deliberately not a multiple of the configured size, so a server that merely
# echoes its old size cannot pass by accident.
#
# Chromium is already open at this point, so the colour assertion here means
# something: the window has to repaint at the new size.
docker cp "$HERE/vncresize.py" "$NAME:/tmp/vncresize.py" > /dev/null 2>&1
RESIZE_OUT="$(docker exec "$NAME" python3 /tmp/vncresize.py 1500 850 5901 2>&1)"
if echo "$RESIZE_OUT" | grep -q "resize=honoured"; then
  ok "desktop resizes on request (SetDesktopSize honoured, $(echo "$RESIZE_OUT" | grep -o 'after=.*' | head -1))"
else
  bad "desktop ignored the resize request"
  echo "$RESIZE_OUT" | sed 's/^/          /'
fi

VNC_RS="$(docker exec "$NAME" python3 /tmp/vncprobe.py 2>&1)"
FB_RS="$(echo "$VNC_RS" | grep -oE 'framebuffer=[0-9]+x[0-9]+' | head -1)"
COL_RS="$(echo "$VNC_RS" | grep -oE 'unique_colors=[0-9]+' | head -1)"
COL_RS="${COL_RS#unique_colors=}"
if [ "${FB_RS#framebuffer=}" = "1500x850" ]; then
  ok "framebuffer reports the requested size after the resize"
else
  bad "framebuffer is ${FB_RS#framebuffer=} after requesting 1500x850"
fi
if [ -n "$COL_RS" ] && [ "$COL_RS" -gt 20 ] 2>/dev/null; then
  ok "the open window repaints at the new size (${COL_RS} unique colours)"
else
  bad "screen went blank after the resize (unique_colours=${COL_RS:-none})"
fi

# --- 7. REGRESSION: Wine prefix, 64/32-bit loaders, real window ----------
# Same detached pattern as the Chromium check: the helper survives the exec
# teardown and the prefix may already have been primed by the Openbox autostart.
docker cp "$HERE/wine-regression.sh" "$NAME:/tmp/wine-regression.sh" > /dev/null 2>&1
docker exec "$NAME" chmod 755 /tmp/wine-regression.sh > /dev/null 2>&1
docker exec "$NAME" rm -f /config/wine-regression.txt > /dev/null 2>&1
docker exec -d "$NAME" /tmp/wine-regression.sh

echo "   waiting up to 240s for the Wine prefix, loaders and notepad window..."
WINE_OUT=""
for _ in $(seq 1 24); do
  sleep 10
  WINE_OUT="$(docker exec "$NAME" cat /config/wine-regression.txt 2>/dev/null)"
  echo "$WINE_OUT" | grep -q '^window=' && break
done

if [ -n "$WINE_OUT" ]; then
  echo "$WINE_OUT" | sed 's/^/          /'
fi

if echo "$WINE_OUT" | grep -q 'wine_version=wine-'; then
  ok "wine runs ($(echo "$WINE_OUT" | grep -o 'wine_version=.*' | head -1 | cut -d= -f2))"
else
  bad "wine --version produced nothing"
fi

if echo "$WINE_OUT" | grep -q 'wine_prefix=ready'; then
  ok "Wine prefix was built under /config"
else
  bad "Wine prefix was not built (see /config/.wine-init.log)"
fi

if echo "$WINE_OUT" | grep -qi 'cmd64=.*Microsoft Windows'; then
  ok "64-bit loader runs a Windows program (wine cmd /c ver)"
else
  bad "64-bit wine could not run cmd (cmd64 missing)"
fi

if echo "$WINE_OUT" | grep -qi 'cmd32=.*Microsoft Windows'; then
  ok "32-bit WoW64 runs an i386 PE (syswow64\\cmd.exe)"
elif echo "$WINE_OUT" | grep -q 'cmd32=no-syswow64'; then
  bad "no syswow64 in the prefix: 32-bit Windows software will not run"
else
  bad "32-bit WoW64 failed to run an i386 PE"
fi

CJK="$(echo "$WINE_OUT" | grep -o 'cjk_fonts=[0-9]*' | head -1)"
CJK="${CJK#cjk_fonts=}"
if [ -n "$CJK" ] && [ "$CJK" -gt 0 ] 2>/dev/null; then
  ok "Wine sees the image's Noto fonts (${CJK} entries via fontconfig)"
else
  bad "Wine registered no Noto fonts; Chinese text in Windows apps shows boxes"
fi

if echo "$WINE_OUT" | grep -qi 'window=.*notepad'; then
  ok "wine-webtop notepad maps a real window"
  echo "$WINE_OUT" | grep -i 'window=.*notepad' | head -1 | sed 's/^/          /'
else
  bad "notepad did NOT map a window (see /tmp/wine-notepad.log)"
fi

# --- 8. the desktop must still paint after all of that -------------------
VNC2="$(docker exec "$NAME" python3 /tmp/vncprobe.py 2>&1)"
COLORS2="$(echo "$VNC2" | grep -oE 'unique_colors=[0-9]+' | head -1)"
COLORS2="${COLORS2#unique_colors=}"
if [ -n "$COLORS2" ] && [ "$COLORS2" -gt 20 ] 2>/dev/null; then
  ok "desktop still paints after the Chromium and Wine tests (${COLORS2} unique colours)"
else
  bad "desktop went blank (unique_colours=${COLORS2:-none})"
fi

echo
echo "=============================================="
echo " passed: $pass   failed: $fail"
echo "=============================================="
echo " Tip: inspect with  docker exec -it ${NAME} supervisorctl status"
[ "$fail" -eq 0 ]
