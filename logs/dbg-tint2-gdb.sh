#!/bin/sh
# Debug harness: run tint2 under gdb so its segfault produces a backtrace.
# Used ad hoc during development; not part of the image.
set -x
apk add --no-cache gdb >/dev/null 2>&1 || echo "gdb install failed"

cat > /etc/supervisor.d/tint2.ini <<'INI'
[program:tint2]
priority=35
user=abc
environment=HOME="/config",DISPLAY="%(ENV_DISPLAY)s",XDG_RUNTIME_DIR="/config/.XDG"
command=/bin/bash -c 'for i in $(seq 1 60); do xset q >/dev/null 2>&1 && break; sleep 1; done; ulimit -c unlimited; exec gdb -batch -ex run -ex "bt full" -ex "info registers rip" --args /usr/bin/tint2'
autorestart=true
startretries=3
stdout_logfile=/var/log/supervisor/tint2-gdb.log
redirect_stderr=true
INI

# monitor: window list + tint2 pid, once a second, into /config/monitor.log
cat > /usr/bin/monitor.sh <<'MON'
#!/bin/sh
export DISPLAY=:1 HOME=/config XDG_RUNTIME_DIR=/config/.XDG
: > /config/monitor.log
i=0
while [ $i -lt 180 ]; do
  echo "t=${i}s tint2pids=$(pgrep tint2 | tr '\n' ',') clients=[$(xprop -root _NET_CLIENT_LIST 2>/dev/null | sed 's/.*# //')] procs=$(ps -eo args | grep -c '[.]exe')" >> /config/monitor.log
  i=$((i+1)); sleep 1
done
MON
chmod 755 /usr/bin/monitor.sh

exec /usr/bin/start-desktop
