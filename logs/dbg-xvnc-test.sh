#!/bin/sh
# Test harness #2: Xvnc as a replacement for Xvfb + x11vnc.
# Ad hoc development harness, not part of the image.
set -x

apk add --no-cache tigervnc >/dev/null 2>&1 || { echo "TIGERVNC INSTALL FAILED"; sleep 3600; exit 1; }

echo "=== sizes ==="
apk info -s tigervnc | tail -1
apk info -s perl xinit gnutls libxfont2 2>/dev/null | grep -A1 "installed size" | grep -v "^--"

echo "=== start Xvnc on :9 (as root, like the image will) ==="
Xvnc :9 -geometry 1280x800 -depth 24 -SecurityTypes None -rfbport 5909 \
     -localhost -AlwaysShared -AcceptSetDesktopSize=1 -desktop test-xvnc \
     >/tmp/xvnc.log 2>&1 &
sleep 5
grep -iE "error|fail|listen" /tmp/xvnc.log | head -5

echo "=== can user abc connect? ==="
su -s /bin/sh abc -c 'DISPLAY=:9 xset q >/dev/null 2>&1 && echo AUTH-OK-as-abc || echo AUTH-FAIL-as-abc'

echo "=== start openbox as abc ==="
su -s /bin/sh abc -c 'DISPLAY=:9 HOME=/home/abc openbox --sm-disable >/tmp/ob.log 2>&1 &'
sleep 3

echo "=== chromium under Xvnc (as abc) ==="
mkdir -p /tmp/ch && chown 1000:1000 /tmp/ch
su -s /bin/sh abc -c 'DISPLAY=:9 HOME=/tmp/ch XDG_RUNTIME_DIR=/tmp/ch setsid /usr/bin/chromium-webtop about:blank >/tmp/cr.log 2>&1 &'
sleep 25
DISPLAY=:9 xwininfo -root -children 2>/dev/null | grep -icE "chromium" || echo "no chromium window"

echo "=== resize to 1600x900 ==="
python3 /tmp/vncresize.py 1600 900 5909

echo "=== harness done, staying alive ==="
sleep 100000
