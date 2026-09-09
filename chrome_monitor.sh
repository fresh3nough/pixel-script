#!/system/bin/sh
# Polls Chrome process table and runs on-device cleanup when Chrome exits.
# ADB-free companion to the Pixel Cleanup app service.

CHROME=com.android.chrome
CLEAN=/data/local/tmp/pixel_cleanup_ondevice.sh
LOG=/data/local/tmp/chrome_monitor.log
STATE=/data/local/tmp/chrome_monitor_state
PIDFILE=/data/local/tmp/chrome_monitor.pid
INTERVAL=2

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null
}

chrome_running() {
  if pidof "$CHROME" >/dev/null 2>&1; then
    return 0
  fi
  # Match chrome package processes only.
  ps -A 2>/dev/null | grep -v grep | grep -q "$CHROME" && return 0
  return 1
}

# Single instance
if [ -f "$PIDFILE" ]; then
  old=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$old" ] && [ "$old" != "$$" ] && kill -0 "$old" 2>/dev/null; then
    # If existing process is this script, exit; else take over.
    cmdline=$(tr '\0' ' ' < /proc/$old/cmdline 2>/dev/null)
    case "$cmdline" in
      *chrome_monitor.sh*) log "INFO already running pid=$old"; exit 0 ;;
    esac
  fi
fi
echo $$ > "$PIDFILE"

if chrome_running; then
  echo running > "$STATE"
else
  echo stopped > "$STATE"
fi
log "INFO monitor start state=$(cat $STATE) pid=$$"

prev=$(cat "$STATE")
stopped_ticks=0
while true; do
  if chrome_running; then
    cur=running
    stopped_ticks=0
  else
    cur=stopped
  fi
  if [ "$prev" = "running" ] && [ "$cur" = "stopped" ]; then
    stopped_ticks=$((stopped_ticks + 1))
    if [ "$stopped_ticks" -ge 2 ]; then
      log "INFO Chrome closed transition running->stopped"
      if [ -f "$CLEAN" ]; then
        /system/bin/sh "$CLEAN" >> "$LOG" 2>&1
        log "INFO cleanup exit=$?"
      else
        log "ERROR missing $CLEAN"
      fi
      prev=stopped
      stopped_ticks=0
    fi
  else
    prev=$cur
  fi
  echo "$prev" > "$STATE"
  sleep "$INTERVAL"
done
