#!/bin/sh
# Host-oriented Android data wipe helper (runs via adb from a workstation).
# Prefer ondevice/pixel_cleanup_ondevice.sh for ADB-free runtime on device.
#
# Permissions / limits:
# 1. Full wipe of other apps' /data/data requires root (adb root / su).
# 2. Chrome: pm clear. GMS: cache-only so Google account login is kept.
# 3. Cookie preserve/restore needs sqlite3 on device, else full DB file copy.

GOOGLE_CHROME_PACKAGE="com.android.chrome"
GOOGLE_ACCOUNTS_PACKAGE="com.google.android.gms"
CHROME_DATA_DIR="/data/data/${GOOGLE_CHROME_PACKAGE}"
# Modern Chrome cookie paths (tried in order)
COOKIE_DB_PRIMARY="${CHROME_DATA_DIR}/app_chrome/Default/Network/Cookies"
COOKIE_DB_SECONDARY="${CHROME_DATA_DIR}/app_chrome/Default/Cookies"
COOKIE_DB_LEGACY="${CHROME_DATA_DIR}/Default/Cookies"
GOOGLE_GMS_DIR="/data/data/${GOOGLE_ACCOUNTS_PACKAGE}"
NON_GOOGLE_APPS=""
PRESERVE_DIR="/data/local/tmp/cookies_preserve"
ADB="${ADB:-/system/bin/adb}"
# Fall back to adb on PATH
if [ ! -x "$ADB" ]; then
  ADB=$(command -v adb 2>/dev/null || echo adb)
fi

TS() { "$ADB" shell "date '+%Y-%m-%d %H:%M:%S'" 2>/dev/null || date '+%Y-%m-%d %H:%M:%S'; }

sh_dev() {
  "$ADB" shell "$@" 2>/dev/null
}

have_device_cmd() {
  sh_dev "command -v $1" >/dev/null 2>&1
}

is_chrome_running() {
  sh_dev "pidof ${GOOGLE_CHROME_PACKAGE}" | grep -q '[0-9]' && return 0
  sh_dev "ps -A" 2>/dev/null | grep -v grep | grep -q "${GOOGLE_CHROME_PACKAGE}"
}

find_cookie_db() {
  for p in "$COOKIE_DB_PRIMARY" "$COOKIE_DB_SECONDARY" "$COOKIE_DB_LEGACY"; do
    if sh_dev "test -f $p && echo yes" | grep -q yes; then
      echo "$p"
      return 0
    fi
  done
  echo ""
}

preserve_login_cookies() {
  echo "$(TS) INFO Preserving login cookies..."
  sh_dev "mkdir -p ${PRESERVE_DIR} && chmod 777 ${PRESERVE_DIR}" || true
  sh_dev "rm -f ${PRESERVE_DIR}/preserved.tsv ${PRESERVE_DIR}/Cookies.bak ${PRESERVE_DIR}/Cookies-journal.bak" || true

  cdb=$(find_cookie_db)
  if [ -z "$cdb" ]; then
    echo "$(TS) INFO no Chrome cookie DB found, skip preserve"
    return 0
  fi

  if have_device_cmd sqlite3; then
    sh_dev "sqlite3 -separator '|' '$cdb' \"SELECT host_key, name, value, expires_utc FROM cookies c WHERE rowid IN (SELECT rowid FROM cookies c2 WHERE c2.host_key = c.host_key ORDER BY last_access_utc DESC LIMIT 1);\" > ${PRESERVE_DIR}/preserved.tsv" || true
    cnt=$(sh_dev "wc -l < ${PRESERVE_DIR}/preserved.tsv" | tr -d ' \r')
    if [ -n "$cnt" ] && [ "$cnt" -gt 0 ] 2>/dev/null; then
      echo "$(TS) INFO Preserved ${cnt} cookies via sqlite3 (one per host)"
      return 0
    fi
    echo "$(TS) WARN sqlite3 preserve empty; falling back to DB file copy"
  else
    echo "$(TS) WARN sqlite3 missing on device; falling back to DB file copy"
  fi

  sh_dev "cp -f '$cdb' ${PRESERVE_DIR}/Cookies.bak" || \
    sh_dev "su -c 'cp -f \"$cdb\" ${PRESERVE_DIR}/Cookies.bak && chmod 666 ${PRESERVE_DIR}/Cookies.bak'" || true
  sh_dev "test -f '${cdb}-journal' && cp -f '${cdb}-journal' ${PRESERVE_DIR}/Cookies-journal.bak" || true
  if sh_dev "test -s ${PRESERVE_DIR}/Cookies.bak && echo yes" | grep -q yes; then
    echo "$(TS) INFO Preserved full cookie DB file"
  else
    echo "$(TS) WARN could not preserve cookie DB"
  fi
}

restore_login_cookies() {
  echo "$(TS) INFO Restoring login cookies..."
  if sh_dev "test -s ${PRESERVE_DIR}/preserved.tsv && echo yes" | grep -q yes; then
    if have_device_cmd sqlite3; then
      cdb=$(find_cookie_db)
      i=0
      while [ -z "$cdb" ] && [ "$i" -lt 5 ]; do
        sleep 1
        cdb=$(find_cookie_db)
        i=$((i + 1))
      done
      if [ -n "$cdb" ]; then
        # Stream TSV and insert row by row on device
        sh_dev "while IFS='|' read -r host name value expiry; do
          [ -z \"\$host\" ] && continue
          shost=\$(echo \"\$host\" | sed \"s/'/''/g\")
          sname=\$(echo \"\$name\" | sed \"s/'/''/g\")
          svalue=\$(echo \"\$value\" | sed \"s/'/''/g\")
          sqlite3 '$cdb' \"INSERT OR REPLACE INTO cookies (host_key, name, value, expires_utc, last_access_utc, creation_utc, path, is_secure, is_httponly, has_expires, is_persistent) VALUES ('\$shost', '\$sname', '\$svalue', \${expiry:-0}, 0, 0, '/', 1, 0, 1, 1);\" 2>/dev/null || true
          echo restored:\$host
        done < ${PRESERVE_DIR}/preserved.tsv"
        echo "$(TS) INFO Login cookies restored via sqlite3"
        return 0
      fi
    fi
  fi

  if sh_dev "test -s ${PRESERVE_DIR}/Cookies.bak && echo yes" | grep -q yes; then
    sh_dev "mkdir -p ${CHROME_DATA_DIR}/app_chrome/Default/Network ${CHROME_DATA_DIR}/app_chrome/Default" || true
    target="$COOKIE_DB_PRIMARY"
    sh_dev "cp -f ${PRESERVE_DIR}/Cookies.bak '$target'" || \
      sh_dev "su -c 'cp -f ${PRESERVE_DIR}/Cookies.bak \"$target\"'" || \
      sh_dev "cp -f ${PRESERVE_DIR}/Cookies.bak '$COOKIE_DB_SECONDARY'" || true
    echo "$(TS) INFO Login cookies restored via full DB file copy"
    return 0
  fi
  echo "$(TS) INFO nothing to restore"
}

wipe_chrome_data() {
  echo "$(TS) INFO Wiping Chrome data preserving login cookies..."
  preserve_login_cookies
  sh_dev "am force-stop ${GOOGLE_CHROME_PACKAGE}" || true
  if sh_dev "pm clear ${GOOGLE_CHROME_PACKAGE}"; then
    echo "$(TS) INFO pm clear ${GOOGLE_CHROME_PACKAGE} ok"
  else
    echo "$(TS) WARN pm clear chrome failed; manual wipe"
    sh_dev "rm -rf ${CHROME_DATA_DIR}/cache ${CHROME_DATA_DIR}/code_cache ${CHROME_DATA_DIR}/app_chrome ${CHROME_DATA_DIR}/app_tabs" || true
  fi
  sh_dev "rm -rf ${CHROME_DATA_DIR}/cache \
                 ${CHROME_DATA_DIR}/code_cache \
                 '${CHROME_DATA_DIR}/app_chrome/Default/Cache' \
                 '${CHROME_DATA_DIR}/app_chrome/Default/Code Cache' \
                 '${CHROME_DATA_DIR}/app_chrome/Default/GPUCache' \
                 '${CHROME_DATA_DIR}/app_chrome/Default/Media Cache' \
                 '${CHROME_DATA_DIR}/app_chrome/Default/Service Worker' \
                 ${CHROME_DATA_DIR}/app_tabs \
                 /sdcard/Android/data/${GOOGLE_CHROME_PACKAGE}/cache" || true
  restore_login_cookies
  echo "$(TS) INFO Chrome data wipe complete"
}

# GMS cache-only — never pm clear (keeps Google account login)
wipe_google_account() {
  echo "$(TS) INFO Wiping GMS caches (account login preserved)..."
  for pkg in ${GOOGLE_ACCOUNTS_PACKAGE} \
             com.google.android.gsf \
             com.google.android.gsf.login \
             com.google.android.googlequicksearchbox \
             com.google.android.gm \
             com.google.android.apps.maps \
             com.google.android.youtube \
             com.google.android.apps.photos
  do
    sh_dev "rm -rf /data/data/${pkg}/cache /data/data/${pkg}/code_cache \
                   /sdcard/Android/data/${pkg}/cache" || true
    sh_dev "su -c 'rm -rf /data/data/${pkg}/cache /data/data/${pkg}/code_cache'" || true
  done
  echo "$(TS) INFO GMS cache wipe complete"
}

wipe_all_app_caches() {
  echo "$(TS) INFO Wiping caches for all apps..."
  # Works without root: Package Manager free-cache request
  sh_dev "pm trim-caches 128G" || sh_dev "cmd package trim-caches 128G" || \
    echo "$(TS) WARN trim-caches unavailable"

  if [ -n "${NON_GOOGLE_APPS}" ]; then
    for app in ${NON_GOOGLE_APPS}; do
      echo "$(TS) INFO Cleaning listed app: ${app}"
      sh_dev "rm -rf /data/data/${app}/cache /data/data/${app}/code_cache" || true
      sh_dev "rm -rf /sdcard/Android/data/${app}/cache" || true
    done
  fi

  # Root: sweep every app cache
  sh_dev "su -c 'for d in /data/data/*/cache /data/data/*/code_cache; do [ -d \"\$d\" ] && rm -rf \"\$d\"/*; done'" || true
  # Non-root external caches
  sh_dev "rm -rf /sdcard/Android/data/*/cache/* /storage/emulated/0/Android/data/*/cache/*" || true
  echo "$(TS) INFO All-app cache cleanup complete"
}

wipe_temp_dirs() {
  echo "$(TS) INFO Wiping temp dirs..."
  # Preserve cleanup tooling under /data/local/tmp
  sh_dev 'for p in /data/local/tmp/*; do
    [ -e "$p" ] || continue
    base=$(basename "$p")
    case "$base" in
      pixel_cleanup.log|pixel_cleanup.lock|pixel_cleanup_ondevice.sh|\
      chrome_monitor.log|chrome_monitor.sh|chrome_monitor_state|chrome_monitor.pid|\
      cookies_preserve) ;;
      *) rm -rf "$p" ;;
    esac
  done' || true
  sh_dev "rm -rf /cache/* /data/local/tmp/dalvik-cache" || true
  sh_dev "su -c 'rm -rf /cache/* /data/cache/* /data/system/cache/* /data/tombstones/* /data/anr/*'" || true
  sh_dev "rm -rf /sdcard/.temp /sdcard/temp /sdcard/tmp /storage/emulated/0/.temp" || true
  sh_dev "find /sdcard -maxdepth 3 -name '*.tmp' -type f -delete" || true
  echo "$(TS) INFO Temp dirs wipe complete"
}

clean_artifacts() {
  echo "$(TS) INFO Cleaning artifacts and bloat..."
  wipe_temp_dirs
  sh_dev "find /sdcard/Download -type f -mtime +7 -delete" || true
  sh_dev "find /storage/emulated/0/Download -type f -mtime +7 -delete" || true
  sh_dev "rm -rf /sdcard/DCIM/.thumbnails /storage/emulated/0/DCIM/.thumbnails" || true
  for wp in com.google.android.webview com.android.webview org.chromium.webview; do
    sh_dev "rm -rf /data/data/${wp}/cache /data/data/${wp}/code_cache" || true
  done
  echo "$(TS) INFO Artifacts cleanup complete"
}

optimize_phone() {
  echo "$(TS) INFO Optimizing phone performance..."
  sh_dev "sync" || true
  sh_dev "su -c 'echo 3 > /proc/sys/vm/drop_caches'" || \
    sh_dev "echo 3 > /proc/sys/vm/drop_caches" || true
  sh_dev "su -c 'rm -rf /data/dalvik-cache/*'" || \
    sh_dev "rm -rf /data/dalvik-cache/*" || true
  echo "$(TS) INFO Performance optimization complete"
}

main() {
  echo "$(TS) INFO === pixel_cleanup.sh starting ==="
  case "$1" in
    --force) force=1 ;;
    *) force=0 ;;
  esac
  if [ "$force" -eq 0 ] && is_chrome_running; then
    echo "$(TS) INFO Chrome is running - no cleanup needed at this time"
  else
    echo "$(TS) INFO Initiating full cleanup (Chrome + all-app caches + temp dirs)..."
    wipe_chrome_data
    wipe_google_account
    wipe_all_app_caches
    clean_artifacts
    optimize_phone
  fi
  echo "$(TS) INFO === pixel_cleanup.sh complete ==="
}

main "$@"
