#!/system/bin/sh
# On-device Pixel cleanup. Runs natively on Android (no host adb).
# Triggered by ChromeCloseMonitor when Chrome leaves the process table.
# Preserves one cookie per host when sqlite3 is available.

LOG=/data/local/tmp/pixel_cleanup.log
STATE=/data/local/tmp/chrome_monitor_state
LOCK=/data/local/tmp/pixel_cleanup.lock
CHROME=com.android.chrome
GMS=com.google.android.gms
CHROME_DATA=/data/data/${CHROME}
COOKIE_DB=${CHROME_DATA}/app_chrome/Default/Cookies
COOKIE_DB_ALT=${CHROME_DATA}/app_chrome/Default/Network/Cookies
PRESERVE_DIR=/data/local/tmp/cookies_preserve
NON_GOOGLE_APPS=""

# Ensure log is world-writable so app UID and shell UID can both append.
ensure_log() {
  touch "$LOG" 2>/dev/null || true
  chmod 666 "$LOG" 2>/dev/null || true
  chmod 777 /data/local/tmp 2>/dev/null || true
}
ensure_log

log() {
  ensure_log
  line="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$line" >> "$LOG" 2>/dev/null || true
  echo "$line"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

chrome_running() {
  pidof "$CHROME" >/dev/null 2>&1 && return 0
  ps -A 2>/dev/null | grep -v grep | grep -q "$CHROME" && return 0
  return 1
}

acquire_lock() {
  if [ -f "$LOCK" ]; then
    oldpid=$(cat "$LOCK" 2>/dev/null)
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
      log "INFO another cleanup running pid=$oldpid, skip"
      return 1
    fi
  fi
  echo $$ > "$LOCK"
  return 0
}

release_lock() {
  rm -f "$LOCK"
}

find_cookie_db() {
  if [ -f "$COOKIE_DB" ]; then
    echo "$COOKIE_DB"
  elif [ -f "$COOKIE_DB_ALT" ]; then
    echo "$COOKIE_DB_ALT"
  else
    echo ""
  fi
}

preserve_login_cookies() {
  cdb=$(find_cookie_db)
  if [ -z "$cdb" ]; then
    log "INFO no Chrome cookie DB found, skip preserve"
    return 0
  fi
  if ! have_cmd sqlite3; then
    log "WARN sqlite3 missing, cannot preserve cookies"
    return 0
  fi
  mkdir -p "$PRESERVE_DIR" 2>/dev/null
  rm -f "$PRESERVE_DIR/preserved.tsv" 2>/dev/null
  # One row per host: most recently accessed cookie name/value/expiry
  sqlite3 -separator '	' "$cdb" \
    "SELECT host_key, name, value, expires_utc FROM cookies c
     WHERE rowid IN (
       SELECT rowid FROM cookies c2
       WHERE c2.host_key = c.host_key
       ORDER BY last_access_utc DESC LIMIT 1
     );" > "$PRESERVE_DIR/preserved.tsv" 2>/dev/null || true
  cnt=$(wc -l < "$PRESERVE_DIR/preserved.tsv" 2>/dev/null || echo 0)
  log "INFO preserved cookie rows=$cnt"
}

restore_login_cookies() {
  if [ ! -s "$PRESERVE_DIR/preserved.tsv" ]; then
    log "INFO nothing to restore"
    return 0
  fi
  if ! have_cmd sqlite3; then
    log "WARN sqlite3 missing, cannot restore cookies"
    return 0
  fi
  # Chrome recreates profile lazily; best-effort restore after wipe
  cdb=$(find_cookie_db)
  if [ -z "$cdb" ]; then
    log "WARN cookie DB not recreated yet, keep preserved.tsv for later"
    return 0
  fi
  while IFS='	' read -r host name value expiry; do
    [ -z "$host" ] && continue
    shost=$(echo "$host" | sed "s/'/''/g")
    sname=$(echo "$name" | sed "s/'/''/g")
    svalue=$(echo "$value" | sed "s/'/''/g")
    sqlite3 "$cdb" "INSERT OR REPLACE INTO cookies
      (host_key, name, value, expires_utc, last_access_utc, creation_utc, path, is_secure, is_httponly, has_expires, is_persistent)
      VALUES ('$shost', '$sname', '$svalue', ${expiry:-0}, 0, 0, '/', 1, 0, 1, 1);" 2>/dev/null || true
    log "INFO restored cookie host=$host"
  done < "$PRESERVE_DIR/preserved.tsv"
}

wipe_chrome() {
  log "INFO wipe Chrome data (preserve login cookies first)"
  preserve_login_cookies
  am force-stop "$CHROME" 2>/dev/null || true
  pm clear "$CHROME" 2>/dev/null || log "WARN pm clear chrome failed (need elevated rights)"
  # Best-effort cache paths when pm clear is blocked
  rm -rf "${CHROME_DATA}/cache" 2>/dev/null || true
  rm -rf "${CHROME_DATA}/code_cache" 2>/dev/null || true
  rm -rf "${CHROME_DATA}/app_chrome/Default/Cache" 2>/dev/null || true
  rm -rf "${CHROME_DATA}/app_chrome/Default/Code Cache" 2>/dev/null || true
  rm -rf "${CHROME_DATA}/app_chrome/Default/GPUCache" 2>/dev/null || true
  rm -rf "${CHROME_DATA}/app_chrome/Default/Media Cache" 2>/dev/null || true
  rm -rf "${CHROME_DATA}/app_chrome/Default/Service Worker" 2>/dev/null || true
  rm -rf "${CHROME_DATA}/app_tabs" 2>/dev/null || true
  restore_login_cookies
  log "INFO Chrome wipe done"
}

wipe_gms_cache() {
  log "INFO wipe GMS caches (not full account sign-out)"
  # Prefer cache-only; full pm clear signs the user out of Google
  rm -rf /data/data/${GMS}/cache 2>/dev/null || true
  rm -rf /data/data/${GMS}/code_cache 2>/dev/null || true
  rm -rf /data/data/com.google.android.gsf/cache 2>/dev/null || true
  rm -rf /data/data/com.google.android.gsf.login/cache 2>/dev/null || true
  log "INFO GMS cache wipe done"
}

wipe_non_google_cache() {
  log "INFO wipe non-Google app caches"
  if [ -z "$NON_GOOGLE_APPS" ]; then
    log "INFO NON_GOOGLE_APPS empty, skip"
    return 0
  fi
  for app in $NON_GOOGLE_APPS; do
    if pm path "$app" >/dev/null 2>&1; then
      log "INFO clean $app"
      rm -rf /data/data/${app}/cache 2>/dev/null || true
      rm -rf /data/data/${app}/code_cache 2>/dev/null || true
    else
      log "WARN missing $app"
    fi
  done
}

clean_artifacts() {
  log "INFO clean artifacts"
  # Do not wipe this script or monitor state under /data/local/tmp wholesale
  rm -rf /cache/* 2>/dev/null || true
  rm -f /data/local/tmp/*.tmp 2>/dev/null || true
  rm -f /data/local/tmp/*.log.bak 2>/dev/null || true
  rm -rf /data/local/tmp/dalvik-cache/* 2>/dev/null || true
  # Downloads leftovers older than 7 days (best effort)
  if have_cmd find; then
    find /sdcard/Download -type f -mtime +7 -delete 2>/dev/null || true
    find /data -maxdepth 3 -name '*.cache' -type f -delete 2>/dev/null || true
  fi
  log "INFO artifacts done"
}

optimize_phone() {
  log "INFO optimize"
  sync 2>/dev/null || true
  # drop_caches needs root; ignore failure
  echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
  rm -rf /data/dalvik-cache/* 2>/dev/null || true
  log "INFO optimize done"
}

run_cleanup() {
  if ! acquire_lock; then
    return 0
  fi
  log "INFO === cleanup start ==="
  wipe_chrome
  wipe_gms_cache
  wipe_non_google_cache
  clean_artifacts
  optimize_phone
  log "INFO === cleanup complete ==="
  release_lock
}

# If invoked with --force, always clean. Else only when Chrome is not running.
case "$1" in
  --force)
    run_cleanup
    ;;
  --status)
    if chrome_running; then echo running; else echo stopped; fi
    ;;
  *)
    if chrome_running; then
      log "INFO Chrome running, skip"
      exit 0
    fi
    run_cleanup
    ;;
esac
