#!/bin/bash
#
# wine-regression.sh -- run INSIDE the container (see scripts/verify.sh).
#
# Proves the Wine stack the image advertises actually works:
#
#   1. the prefix gets built (the Openbox autostart primes it in the background)
#   2. the 64-bit loader runs a Windows program          (wine cmd /c ver)
#   3. the 32-bit i386 path runs through Wine's new WoW64 layer, which is why
#      Alpine needs no multilib for 32-bit Windows software
#   4. Wine discovers the image's system fonts through fontconfig, so Chinese
#      text inside a Windows app renders instead of showing boxes
#   5. `wine-webtop notepad` -- the exact command the Openbox menu runs -- maps
#      a real window
#
# IMPORTANT: every wine command here runs as user abc, with HOME=/config. That
# is how the desktop runs it. Running wine as root hits a DIFFERENT wineserver
# (/tmp/.wine-0 vs /tmp/.wine-1000) against a prefix owned by abc, and the
# commands then produce no output at all -- which looks exactly like "Wine is
# broken" while the app itself works fine from the menu.
#
# The window test uses the same setsid trick as chromium-regression.sh: without
# it, tearing down the exec session kills the process group before the window is
# mapped, producing a false failure.
#
# Writes key=value findings to /config/wine-regression.txt.
#
set -u

OUT=/config/wine-regression.txt
: > "$OUT"

# --- 1. wait for the prefix ------------------------------------------------
# wine-prefix-init runs from the Openbox autostart; on a fresh volume wineboot
# needs ~10-30s.
for _ in $(seq 1 90); do
  [ -d /config/.wine/drive_c/windows ] && break
  sleep 2
done

# Run a command as the desktop user, with the environment the desktop uses.
as_abc() {
  su -s /bin/bash abc -c "
    export DISPLAY=:1 HOME=/config XDG_RUNTIME_DIR=/config/.XDG
    export WINEPREFIX=/config/.wine WINEDEBUG=-all
    export WINEDLLOVERRIDES='mscoree,mshtml='
    $1" 2>/dev/null
}

{
  echo "wine_version=$(wine --version 2>&1 | head -1)"
  if [ -d /config/.wine/drive_c/windows ]; then
    echo "wine_prefix=ready"
  else
    echo "wine_prefix=missing"
  fi

  # --- 2. 64-bit Windows program ------------------------------------------
  echo "cmd64=$(as_abc 'wine cmd /c ver' | tr -d '\r' | grep -i 'Microsoft Windows' | head -1)"

  # --- 3. 32-bit i386 PE through Wine's new WoW64 layer -------------------
  if [ -f /config/.wine/drive_c/windows/syswow64/cmd.exe ]; then
    echo "cmd32=$(as_abc 'wine "C:\windows\syswow64\cmd.exe" /c ver' | tr -d '\r' | grep -i 'Microsoft Windows' | head -1)"
  else
    echo "cmd32=no-syswow64"
  fi

  # --- 4. fontconfig-provided fonts (Noto CJK) ----------------------------
  echo "cjk_fonts=$(as_abc 'wine reg query "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Fonts"' | grep -ci noto)"
} >> "$OUT" 2>&1

# --- 5. window test: the command the menu item runs ------------------------
setsid su -s /bin/bash abc -c \
  "DISPLAY=:1 HOME=/config XDG_RUNTIME_DIR=/config/.XDG /usr/bin/wine-webtop notepad" \
  >/tmp/wine-notepad.log 2>&1 </dev/null &

sleep 25

{
  echo "notepad_procs=$(ps -eo args | grep -c '[n]otepad')"
  for w in $(DISPLAY=:1 xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -oE '0x[0-9a-f]+'); do
    name="$(DISPLAY=:1 xprop -id "$w" _NET_WM_NAME 2>/dev/null)"
    class="$(DISPLAY=:1 xprop -id "$w" WM_CLASS 2>/dev/null)"
    echo "window=${name} ${class}"
  done
} >> "$OUT" 2>&1

exit 0
