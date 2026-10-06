#!/bin/bash
#
# chromium-regression.sh -- run INSIDE the container (see scripts/verify.sh).
#
# Verifies the original bug: launching Chromium the way the Openbox menu does
# must actually open a browser window.
#
# Run detached (`docker exec -d`) so that tearing down the exec session does not
# kill Chromium's process group before it maps its window -- that teardown is
# what makes this test falsely fail.
#
# Writes its findings to /abc/chromium-regression.txt.
#
set -u

export DISPLAY="${DISPLAY:-:1}"
OUT=/abc/chromium-regression.txt

pkill -f "lib/chromium/chromium" 2>/dev/null || true
sleep 2

# setsid detaches Chromium into its own session so it survives this script.
setsid su -s /bin/bash abc -c \
  "DISPLAY=${DISPLAY} HOME=/abc XDG_RUNTIME_DIR=/abc/.XDG /usr/bin/chromium-webtop about:blank" \
  > /tmp/chromium-regression.log 2>&1 < /dev/null &

# Chromium needs a while on first run: it creates a profile before mapping.
sleep 30

{
  echo "procs=$(ps -eo args | grep -c '[l]ib/chromium/chromium')"
  for w in $(DISPLAY="${DISPLAY}" xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -oE '0x[0-9a-f]+'); do
    DISPLAY="${DISPLAY}" xprop -id "$w" _NET_WM_NAME 2>/dev/null
  done
} > "$OUT" 2>&1

exit 0
