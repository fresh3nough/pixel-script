#!/system/bin/sh
# On-device Pixel cleanup. Runs natively on Android (no host adb).
# Triggered by ChromeCloseMonitor when Chrome leaves the process table.
# Preserves one cookie per host when sqlite3 is available; falls back to
# full cookie DB file copy when sqlite3 is missing.
#
# Permissions / limits handled here:
# 1. Full wipe of other apps' /data/data uses su when present; without root,
#    falls back to pm clear (Chrome), pm trim-caches (all apps), and public dirs.
# 2. Chrome: pm clear. GMS: cache-only so Google account login is kept.
# 3. Cookie preserve/restore: sqlite3 preferred; DB file backup if absent.

LOG=/data/local/tmp/pixel_cleanup.log
STATE=/data/local/tmp/chrome_monitor_state
LOCK=/data/local/tmp/pixel_cleanup.lock
CHROME=com.android.chrome
GMS=com.google.android.gms
CHROME_DATA=/data/data/${CHROME}
COOKIE_DB=${CHROME_DATA}/app_chrome/Default/Cookies
COOKIE_DB_ALT=${CHROME_DATA}/app_chrome/Default/Network/Cookies
PRESERVE_DIR=/data/local/tmp/cookies_preserve
# Optional space-separated package list for extra targeted cache wipes.
# Leave empty to rely on global trim-caches + root all-app cache sweep.
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

# Root helper: run command as root when su is available.
# Sets HAVE_ROOT=1/0 on first probe.
HAVE_ROOT=""
probe_root() {
  if [ -n "$HAVE_ROOT" ]; then
    return "$HAVE_ROOT"
  fi
  if have_cmd su; then
    if su -c 'id' 2>/dev/null | grep -q 'uid=0'; then
      HAVE_ROOT=0
      log "INFO root available via su"
      return 0
    fi
  fi
  HAVE_ROOT=1
  log "INFO no root; using non-privileged wipe paths"
  return 1
}

as_root() {
  if probe_root; then
    su -c "$*" 2>/dev/null
    return $?
  fi
  return 1
}

# rm that tries root when plain rm cannot reach the path.
rm_rf() {
  path="$1"
  [ -z "$path" ] && return 0
  rm -rf "$path" 2>/dev/null && return 0
  as_root "rm -rf '$path'" >/dev/null 2>&1 || true
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
    # Root may still read the private path
    if as_root "test -f '$COOKIE_DB'" >/dev/null 2>&1; then
      echo "$COOKIE_DB"
    elif as_root "test -f '$COOKIE_DB_ALT'" >/dev/null 2>&1; then
      echo "$COOKIE_DB_ALT"
    else
      echo ""
    fi
  fi
}

# Copy a file; fall back to root cat when needed.
copy_file() {
  src="$1"
  dst="$2"
  if cp -f "$src" "$dst" 2>/dev/null; then
    return 0
  fi
  if as_root "cp -f '$src' '$dst' && chmod 666 '$dst'" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

preserve_login_cookies() {
  cdb=$(find_cookie_db)
  if [ -z "$cdb" ]; then
    log "INFO no Chrome cookie DB found, skip preserve"
    return 0
  fi
  mkdir -p "$PRESERVE_DIR" 2>/dev/null || true
  chmod 777 "$PRESERVE_DIR" 2>/dev/null || true
  rm -f "$PRESERVE_DIR/preserved.tsv" "$PRESERVE_DIR/Cookies.bak" \
        "$PRESERVE_DIR/Cookies-journal.bak" 2>/dev/null || true

  # Preferred: one cookie per host via sqlite3
  if have_cmd sqlite3; then
    # May need root to read Chrome private data
    if [ -r "$cdb" ]; then
      sqlite3 -separator '	' "$cdb" \
        "SELECT host_key, name, value, expires_utc FROM cookies c
         WHERE rowid IN (
           SELECT rowid FROM cookies c2
           WHERE c2.host_key = c.host_key
           ORDER BY last_access_utc DESC LIMIT 1
         );" > "$PRESERVE_DIR/preserved.tsv" 2>/dev/null || true
    else
      as_root "sqlite3 -separator '	' '$cdb' \"SELECT host_key, name, value, expires_utc FROM cookies c WHERE rowid IN (SELECT rowid FROM cookies c2 WHERE c2.host_key = c.host_key ORDER BY last_access_utc DESC LIMIT 1);\"" \
        > "$PRESERVE_DIR/preserved.tsv" 2>/dev/null || true
    fi
    cnt=$(wc -l < "$PRESERVE_DIR/preserved.tsv" 2>/dev/null | tr -d ' ' || echo 0)
    if [ -n "$cnt" ] && [ "$cnt" -gt 0 ] 2>/dev/null; then
      log "INFO preserved cookie rows=$cnt via sqlite3"
      return 0
    fi
    log "WARN sqlite3 preserve returned empty; falling back to DB file copy"
  else
    log "WARN sqlite3 missing, falling back to full cookie DB file copy"
  fi

  # Fallback (limit #3): preserve entire Cookies DB so restore works without sqlite3
  if copy_file "$cdb" "$PRESERVE_DIR/Cookies.bak"; then
    # journal optional
    if [ -f "${cdb}-journal" ]; then
      copy_file "${cdb}-journal" "$PRESERVE_DIR/Cookies-journal.bak" || true
    fi
    log "INFO preserved full cookie DB file from $cdb"
  else
    log "WARN could not preserve cookie DB (need readable path or root)"
  fi
}

restore_login_cookies() {
  # Path A: row-level restore via sqlite3
  if [ -s "$PRESERVE_DIR/preserved.tsv" ] && have_cmd sqlite3; then
    cdb=$(find_cookie_db)
    if [ -z "$cdb" ]; then
      # Wait briefly for Chrome profile recreation after pm clear
      i=0
      while [ "$i" -lt 5 ]; do
        sleep 1
        cdb=$(find_cookie_db)
        [ -n "$cdb" ] && break
        i=$((i + 1))
      done
    fi
    if [ -z "$cdb" ]; then
      log "WARN cookie DB not recreated yet, keep preserved.tsv for later"
    else
      while IFS='	' read -r host name value expiry; do
        [ -z "$host" ] && continue
        shost=$(echo "$host" | sed "s/'/''/g")
        sname=$(echo "$name" | sed "s/'/''/g")
        svalue=$(echo "$value" | sed "s/'/''/g")
        sql="INSERT OR REPLACE INTO cookies
          (host_key, name, value, expires_utc, last_access_utc, creation_utc, path, is_secure, is_httponly, has_expires, is_persistent)
          VALUES ('$shost', '$sname', '$svalue', ${expiry:-0}, 0, 0, '/', 1, 0, 1, 1);"
        if [ -w "$cdb" ] || [ -f "$cdb" ]; then
          sqlite3 "$cdb" "$sql" 2>/dev/null || \
            as_root "sqlite3 '$cdb' \"$sql\"" >/dev/null 2>&1 || true
        else
          as_root "sqlite3 '$cdb' \"$sql\"" >/dev/null 2>&1 || true
        fi
        log "INFO restored cookie host=$host"
      done < "$PRESERVE_DIR/preserved.tsv"
      return 0
    fi
  fi

  # Path B: full DB file restore (no sqlite3 required)
  if [ -s "$PRESERVE_DIR/Cookies.bak" ]; then
    # Ensure Chrome profile dirs exist after pm clear
    for base in \
      "${CHROME_DATA}/app_chrome/Default" \
      "${CHROME_DATA}/app_chrome/Default/Network"
    do
      mkdir -p "$base" 2>/dev/null || as_root "mkdir -p '$base'" >/dev/null 2>&1 || true
    done
    # Prefer Network/Cookies (modern Chrome), else Default/Cookies
    target="$COOKIE_DB_ALT"
    parent=$(dirname "$target")
    if [ ! -d "$parent" ]; then
      target="$COOKIE_DB"
      parent=$(dirname "$target")
      mkdir -p "$parent" 2>/dev/null || as_root "mkdir -p '$parent'" >/dev/null 2>&1 || true
    fi
    if copy_file "$PRESERVE_DIR/Cookies.bak" "$target"; then
      [ -f "$PRESERVE_DIR/Cookies-journal.bak" ] && \
        copy_file "$PRESERVE_DIR/Cookies-journal.bak" "${target}-journal" || true
      # Fix ownership when running as root so Chrome can read it
      if probe_root; then
        owner=$(su -c "stat -c %u:%g '$CHROME_DATA'" 2>/dev/null || true)
        [ -z "$owner" ] && owner=$(su -c "ls -ldn '$CHROME_DATA' 2>/dev/null" | awk '{print $3":"$4}')
        [ -n "$owner" ] && su -c "chown $owner '$target' 2>/dev/null; [ -f '${target}-journal' ] && chown $owner '${target}-journal'" >/dev/null 2>&1 || true
      fi
      log "INFO restored full cookie DB to $target"
    else
      log "WARN full cookie DB restore failed"
    fi
    return 0
  fi

  log "INFO nothing to restore"
}

wipe_chrome() {
  log "INFO wipe Chrome data (preserve login cookies first)"
  preserve_login_cookies
  am force-stop "$CHROME" 2>/dev/null || true
  # Limit #2: pm clear works for Chrome without root on user builds
  if pm clear "$CHROME" 2>/dev/null; then
    log "INFO pm clear $CHROME ok"
  else
    log "WARN pm clear chrome failed (need shell/root); manual path wipe"
    rm_rf "${CHROME_DATA}/cache"
    rm_rf "${CHROME_DATA}/code_cache"
    rm_rf "${CHROME_DATA}/app_chrome"
    rm_rf "${CHROME_DATA}/app_tabs"
    rm_rf "${CHROME_DATA}/app_textures"
    rm_rf "${CHROME_DATA}/files"
    rm_rf "${CHROME_DATA}/no_backup"
  fi
  # Best-effort leftovers either way
  rm_rf "${CHROME_DATA}/cache"
  rm_rf "${CHROME_DATA}/code_cache"
  rm_rf "${CHROME_DATA}/app_chrome/Default/Cache"
  rm_rf "${CHROME_DATA}/app_chrome/Default/Code Cache"
  rm_rf "${CHROME_DATA}/app_chrome/Default/GPUCache"
  rm_rf "${CHROME_DATA}/app_chrome/Default/Media Cache"
  rm_rf "${CHROME_DATA}/app_chrome/Default/Service Worker"
  rm_rf "${CHROME_DATA}/app_chrome/Default/Local Storage"
  rm_rf "${CHROME_DATA}/app_chrome/Default/Session Storage"
  rm_rf "${CHROME_DATA}/app_chrome/Default/Sessions"
  rm_rf "${CHROME_DATA}/app_chrome/Default/History"
  rm_rf "${CHROME_DATA}/app_tabs"
  # External Chrome caches / downloads scratch
  rm_rf "/sdcard/Android/data/${CHROME}/cache"
  rm_rf "/storage/emulated/0/Android/data/${CHROME}/cache"
  restore_login_cookies
  log "INFO Chrome wipe done"
}

wipe_gms_cache() {
  log "INFO wipe GMS caches (not full account sign-out)"
  # Limit #2: cache-only by design — never pm clear GMS
  for pkg in "$GMS" com.google.android.gsf com.google.android.gsf.login \
             com.google.android.googlequicksearchbox com.google.android.apps.maps \
             com.google.android.youtube com.google.android.gm \
             com.google.android.apps.photos com.google.android.contacts \
             com.google.android.calendar com.google.android.apps.messaging \
             com.google.android.inputmethod.latin
  do
    rm_rf "/data/data/${pkg}/cache"
    rm_rf "/data/data/${pkg}/code_cache"
    rm_rf "/sdcard/Android/data/${pkg}/cache"
    rm_rf "/storage/emulated/0/Android/data/${pkg}/cache"
  done
  log "INFO GMS cache wipe done"
}

# Global cache free without enumerating packages (works without root).
trim_all_app_caches() {
  log "INFO trim-caches for all apps"
  # Request a very large free-bytes target so Package Manager clears caches broadly
  if pm trim-caches 128G 2>/dev/null; then
    log "INFO pm trim-caches 128G ok"
  elif cmd package trim-caches 128G 2>/dev/null; then
    log "INFO cmd package trim-caches 128G ok"
  else
    log "WARN trim-caches unavailable"
  fi
}

wipe_all_app_caches() {
  log "INFO wipe caches for all apps (beyond Chrome)"
  trim_all_app_caches

  # Explicit list if caller set NON_GOOGLE_APPS
  if [ -n "$NON_GOOGLE_APPS" ]; then
    for app in $NON_GOOGLE_APPS; do
      if pm path "$app" >/dev/null 2>&1; then
        log "INFO clean listed app $app"
        rm_rf "/data/data/${app}/cache"
        rm_rf "/data/data/${app}/code_cache"
        rm_rf "/sdcard/Android/data/${app}/cache"
      else
        log "WARN missing $app"
      fi
    done
  fi

  # Limit #1: with root, sweep every package cache under /data/data and external
  if probe_root; then
    log "INFO root sweep of /data/data/*/cache and code_cache"
    as_root 'for d in /data/data/*/cache /data/data/*/code_cache; do [ -d "$d" ] && rm -rf "$d"/*; done' >/dev/null 2>&1 || true
    as_root 'for d in /sdcard/Android/data/*/cache /storage/emulated/0/Android/data/*/cache; do [ -d "$d" ] && rm -rf "$d"/*; done' >/dev/null 2>&1 || true
    # WebView / trichrome caches
    as_root 'rm -rf /data/data/com.google.android.webview/cache \
                    /data/data/com.google.android.webview/code_cache \
                    /data/data/com.android.webview/cache \
                    /data/data/com.android.chrome/app_webview 2>/dev/null' >/dev/null 2>&1 || true
  else
    # Non-root: clear external (world-accessible) app caches
    log "INFO non-root external Android/data cache sweep"
    if have_cmd find; then
      find /sdcard/Android/data -type d -name cache 2>/dev/null | while read -r d; do
        rm -rf "$d"/* 2>/dev/null || true
      done
      find /storage/emulated/0/Android/data -type d -name cache 2>/dev/null | while read -r d; do
        rm -rf "$d"/* 2>/dev/null || true
      done
    else
      rm -rf /sdcard/Android/data/*/cache/* 2>/dev/null || true
      rm -rf /storage/emulated/0/Android/data/*/cache/* 2>/dev/null || true
    fi
  fi
  log "INFO all-app cache wipe done"
}

wipe_temp_dirs() {
  log "INFO wipe temp dirs"
  # Preserve our own runtime files under /data/local/tmp
  # Wipe everything else in common temp locations.
  if have_cmd find; then
    find /data/local/tmp -mindepth 1 -maxdepth 1 2>/dev/null | while read -r p; do
      base=$(basename "$p")
      case "$base" in
        pixel_cleanup.log|pixel_cleanup.lock|pixel_cleanup_ondevice.sh|\
        chrome_monitor.log|chrome_monitor.sh|chrome_monitor_state|chrome_monitor.pid|\
        cookies_preserve)
          ;;
        *)
          rm_rf "$p"
          ;;
      esac
    done
  else
    # Fallback glob without deleting protected names
    for p in /data/local/tmp/*; do
      [ -e "$p" ] || continue
      base=$(basename "$p")
      case "$base" in
        pixel_cleanup.log|pixel_cleanup.lock|pixel_cleanup_ondevice.sh|\
        chrome_monitor.log|chrome_monitor.sh|chrome_monitor_state|chrome_monitor.pid|\
        cookies_preserve) ;;
        *) rm_rf "$p" ;;
      esac
    done
  fi

  rm_rf /data/local/tmp/dalvik-cache
  rm_rf /data/local/tmp/.*.tmp
  # System cache partition
  rm_rf /cache/lost+found
  if probe_root; then
    as_root 'rm -rf /cache/* /data/cache/* /data/system/cache/* /data/system/dropbox/* 2>/dev/null' >/dev/null 2>&1 || true
    as_root 'rm -rf /data/tombstones/* /data/anr/* 2>/dev/null' >/dev/null 2>&1 || true
  else
    rm -rf /cache/* 2>/dev/null || true
  fi

  # App-specific temp / download scratch on shared storage
  for d in \
    /sdcard/.temp /sdcard/temp /sdcard/tmp \
    /sdcard/Android/data/*/cache \
    /storage/emulated/0/.temp /storage/emulated/0/temp
  do
    rm -rf $d 2>/dev/null || true
  done

  # *.tmp leftovers
  if have_cmd find; then
    find /data/local/tmp -name '*.tmp' -type f -delete 2>/dev/null || true
    find /sdcard -maxdepth 3 -name '*.tmp' -type f -delete 2>/dev/null || true
  fi
  log "INFO temp dirs wipe done"
}

clean_artifacts() {
  log "INFO clean artifacts"
  wipe_temp_dirs

  # Downloads leftovers older than 7 days (best effort)
  if have_cmd find; then
    find /sdcard/Download -type f -mtime +7 -delete 2>/dev/null || true
    find /storage/emulated/0/Download -type f -mtime +7 -delete 2>/dev/null || true
    find /sdcard/Android/data -name '*.cache' -type f -delete 2>/dev/null || true
    # Thumbnails
    find /sdcard/DCIM -name '.thumbnails' -type d 2>/dev/null | while read -r t; do
      rm -rf "$t"/* 2>/dev/null || true
    done
    rm_rf /sdcard/DCIM/.thumbnails
    rm_rf /storage/emulated/0/DCIM/.thumbnails
  fi

  # WebView package cache (safe; not a full clear of GMS)
  for wp in com.google.android.webview com.android.webview org.chromium.webview; do
    rm_rf "/data/data/${wp}/cache"
    rm_rf "/data/data/${wp}/code_cache"
  done

  log "INFO artifacts done"
}

optimize_phone() {
  log "INFO optimize"
  sync 2>/dev/null || true
  # drop_caches needs root; ignore failure
  if probe_root; then
    as_root 'echo 3 > /proc/sys/vm/drop_caches' >/dev/null 2>&1 || true
    as_root 'rm -rf /data/dalvik-cache/*' >/dev/null 2>&1 || true
  else
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    rm -rf /data/dalvik-cache/* 2>/dev/null || true
  fi
  log "INFO optimize done"
}

run_cleanup() {
  if ! acquire_lock; then
    return 0
  fi
  # Probe once up front so logs show privilege mode
  probe_root || true
  log "INFO === cleanup start ==="
  wipe_chrome
  wipe_gms_cache
  wipe_all_app_caches
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
  --root-status)
    if probe_root; then echo root; else echo unprivileged; fi
    ;;
  *)
    if chrome_running; then
      log "INFO Chrome running, skip"
      exit 0
    fi
    run_cleanup
    ;;
esac
