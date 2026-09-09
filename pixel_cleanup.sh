#!/system/bin/sh
# Android data wipe and phone optimization script
# Performs comprehensive cleanup of Google data, accounts, cache, and phone optimization
# 
# IMPORTANT: This script uses adb shell commands and requires ADB connection to device.
# For ADB-independent execution, install Termux on your Pixel and run the script there.
#
# For auto-execution on Chrome closure: requires Android Java/Kotlin BroadcastReceiver
# or Termux with Chrome monitoring add-on.

GOOGLE_CHROME_PACKAGE="com.android.chrome"
GOOGLE_ACCOUNTS_PACKAGE="com.google.android.gms"
CHROME_DATA_DIR="/data/data/${GOOGLE_CHROME_PACKAGE}"
GOOGLE_GMS_DIR="/data/data/${GOOGLE_ACCOUNTS_PACKAGE}"
NON_GOOGLE_APPS=""

# Simple timestamp
TS() { /system/bin/adb shell "date '+%Y-%m-%d %H:%M:%S'" 2>/dev/null || echo "TIME"; }

# Check if Chrome is running (uses adb, requires ADB connection)
is_chrome_running() {
    /system/bin/adb shell "ps | grep -v grep | grep -q ${GOOGLE_CHROME_PACKAGE}" 2>/dev/null
    [ $? -eq 0 ]
}

# Wipe Chrome data preserving one cookie per domain for login persistence
wipe_chrome_data() {
    echo "$(TS) INFO Wiping Chrome data preserving login cookies..."
    
    # Preserve one cookie per domain before clearing
    /system/bin/adb shell "mkdir -p /tmp/cookies_preserve 2>/dev/null" || true
    
    if /system/bin/adb shell "test -f ${CHROME_DATA_DIR}/Default/Cookies" 2>/dev/null; then
        /system/bin/adb shell "sqlite3 -separator '|' ${CHROME_DATA_DIR}/Default/Cookies \
            'SELECT host, name, value, expiry, lastAccessTime FROM cookies' \
            > /tmp/cookies_preserve/all_cookies.txt 2>/dev/null" || true
        
        if [ -s /tmp/cookies_preserve/all_cookies.txt ]; then
            /system/bin/adb shell "sqlite3 /tmp/cookies_preserve/preserved.db \
                'CREATE TABLE IF NOT EXISTS cookies (host TEXT, name TEXT, value TEXT, expiry INTEGER);' 2>/dev/null || true"
            
            # Get unique domains and preserve one cookie each (most recently accessed)
            domains=$(/system/bin/adb shell "sqlite3 -separator '|' ${CHROME_DATA_DIR}/Default/Cookies \
                'SELECT DISTINCT host FROM cookies' 2>/dev/null" | tr '\n' ' ') || true
            
            preserved_count=0
            for d in $domains; do
                [ -z "$d" ] && continue
                cookie_info=$(/system/bin/adb shell "sqlite3 -separator '|' ${CHROME_DATA_DIR}/Default/Cookies \
                    'SELECT host, name, value, expiry, lastAccessTime FROM cookies WHERE host = '${d}' ORDER BY lastAccessTime DESC LIMIT 1' 2>/dev/null") || true
                
                if [ -n "$cookie_info" ]; then
                    set -- $cookie_info
                    safe_host=$(echo "$1" | sed "s/'/''/g")
                    safe_name=$(echo "$2" | sed "s/'/''/g")
                    safe_value=$(echo "$3" | sed "s/'/''/g")
                    
                    /system/bin/adb shell "sqlite3 /tmp/cookies_preserve/preserved.db \
                        \"INSERT OR REPLACE INTO cookies (host, name, value, expiry) VALUES ('${safe_host}', '${safe_name}', '${safe_value}', ${4});\" 2>/dev/null || true"
                    
                    preserved_count=$((preserved_count + 1))
                    echo "$(TS) INFO Preserved cookie for: ${safe_host}"
                fi
            done
            echo "$(TS) INFO Preserved ${preserved_count} cookies total (one per domain)"
        fi
    fi
    
    # Clear all Chrome data (pm clear deletes all cookies, cache, site data)
    /system/bin/adb shell "pm clear ${GOOGLE_CHROME_PACKAGE}" 2>/dev/null || true
    /system/bin/adb shell "rm -rf ${CHROME_DATA_DIR}" 2>/dev/null || true
    /system/bin/adb shell "rm -rf /data/data/${GOOGLE_CHROME_PACKAGE}/cache" 2>/dev/null || true
    /system/bin/adb shell "rm -rf /data/data/${GOOGLE_CHROME_PACKAGE}/app_chrome*" 2>/dev/null || true
    /system/bin/adb shell "rm -rf /data/data/${GOOGLE_CHROME_PACKAGE}/File/*" 2>/dev/null || true
    /system/bin/adb shell "rm -rf /data/data/${GOOGLE_CHROME_PACKAGE}/GPUCache" 2>/dev/null || true
    /system/bin/adb shell "rm -rf /data/data/${GOOGLE_CHROME_PACKAGE}/Media*Cache*" 2>/dev/null || true
    
    # Restore preserved login cookies
    if [ -f /tmp/cookies_preserve/preserved.db ] && [ "$preserved_count" -gt 0 ]; then
        preserved_hosts=$(/system/bin/adb shell "sqlite3 /tmp/cookies_preserve/preserved.db 'SELECT host FROM cookies' 2>/dev/null" | tr '\n' ' ') || true
        for host in $preserved_hosts; do
            [ -z "$host" ] && continue
            cookie_data=$(/system/bin/adb shell "sqlite3 /tmp/cookies_preserve/preserved.db \
                'SELECT name, value, expiry FROM cookies WHERE host = '${host};' 2>/dev/null") || true
            if [ -n "$cookie_data" ]; then
                set -- $cookie_data
                r_name="$1"
                r_value="$2"
                r_expiry="$3"
                safe_host=$(echo "$host" | sed "s/'/''/g")
                safe_name=$(echo "$r_name" | sed "s/'/''/g")
                safe_value=$(echo "$r_value" | sed "s/'/''/g")
                /system/bin/adb shell "sqlite3 ${CHROME_DATA_DIR}/Default/Cookies \
                    \"INSERT OR REPLACE INTO cookies (host, name, value, expiry, lastAccessTime, creationTime) \
                    VALUES ('${safe_host}', '${safe_name}', '${safe_value}', ${r_expiry}, $(/system/bin/adb shell "date +%s" 2>/dev/null), $(/system/bin/adb shell "date +%s" 2>/dev/null));\" 2>/dev/null || true"
                echo "$(TS) INFO Restored cookie for: ${host}"
            fi
        done
        echo "$(TS) INFO Login cookies restored for persistent login state"
    fi
    
    echo "$(TS) INFO Chrome data wipe complete"
}

# Wipe Google account data (GMS, auth tokens, etc.)
wipe_google_account() {
    echo "$(TS) INFO Wiping Google account data..."
    /system/bin/adb shell "pm clear ${GOOGLE_ACCOUNTS_PACKAGE}" 2>/dev/null || true
    /system/bin/adb shell "rm -rf ${GOOGLE_GMS_DIR}/cache" 2>/dev/null || true
    /system/bin/adb shell "rm -rf ${GOOGLE_GMS_DIR}/databases" 2>/dev/null || true
    /system/bin/adb shell "rm -rf /data/misc/credentials/*" 2>/dev/null || true
    /system/bin/adb shell "rm -rf /data/misc/user/0/com.google/*" 2>/dev/null || true
    echo "$(TS) INFO Google account data wipe complete"
}

# Wipe non-Google app cache (specify apps: e.g., NON_GOOGLE_APPS="app1 app2")
wipe_non_google_cache() {
    echo "$(TS) INFO Wiping non-Google app cache..."
    if [ -n "${NON_GOOGLE_APPS}" ]; then
        for app in ${NON_GOOGLE_APPS}; do
            if /system/bin/adb shell "pm list packages -e | grep -q ${app}" 2>/dev/null; then
                echo "$(TS) INFO Cleaning: ${app}"
                /system/bin/adb shell "pm clear ${app}" 2>/dev/null || true
                /system/bin/adb shell "rm -rf /data/data/${app}/cache" 2>/dev/null || true
                /system/bin/adb shell "rm -rf /data/data/${app}/app_compat*" 2>/dev/null || true
            else
                echo "$(TS) WARN App not found: ${app}"
            fi
        done
    else
        echo "$(TS) INFO No non-Google apps specified, skipping"
    fi
    echo "$(TS) INFO Non-Google app cache cleanup complete"
}

# Clean artifacts and bloat (expanded scope)
clean_artifacts() {
    echo "$(TS) INFO Cleaning artifacts and bloat..."
    /system/bin/adb shell "rm -rf /cache/*" 2>/dev/null || true
    /system/bin/adb shell "rm -rf /data/local/tmp/*" 2>/dev/null || true
    /system/bin/adb shell "rm -rf /storage/emulated/0/Download/*" 2>/dev/null || true
    /system/bin/adb shell "rm -rf /data/system/cache/*" 2>/dev/null || true
    /system/bin/adb shell "rm -rf /data/uicc/*" 2>/dev/null || true
    WEBSITE_PKG="org.chromium.webview"
    if /system/bin/adb shell "pm list packages -e | grep -q ${WEBSITE_PKG}" 2>/dev/null; then
        /system/bin/adb shell "pm clear ${WEBSITE_PKG}" 2>/dev/null || true
        /system/bin/adb shell "rm -rf /data/data/${WEBSITE_PACKAGE}/cache" 2>/dev/null || true
    fi
    /system/bin/adb shell "find /data -maxdepth 3 -name '*.cache' -type f -delete" 2>/dev/null || true
    /system/bin/adb shell "find /data -maxdepth 3 -name '*.log' -type f -delete" 2>/dev/null || true
    /system/bin/adb shell "find /data/media/0 -name '*.thumbnail' -type f -delete" 2>/dev/null || true
    /system/bin/adb shell "find /data/media/0 -maxdepth 2 -name '*.jpg' -type f -mtime +30 -delete" 2>/dev/null || true
    /system/bin/adb shell "find /data/media/0 -maxdepth 2 -name '*.png' -type f -mtime +30 -delete" 2>/dev/null || true
    echo "$(TS) INFO Artifacts cleanup complete"
}

# Optimize phone performance (expanded scope)
optimize_phone() {
    echo "$(TS) INFO Optimizing phone performance..."
    /system/bin/adb shell "sync" 2>/dev/null || true
    /system/bin/adb shell "echo 'powersave' > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" 2>/dev/null || true
    /system/bin/adb shell "rm -rf /data/dalvik-cache/*" 2>/dev/null || true
    /system/bin/adb shell "rm -rf /data/data/*/cache/*" 2>/dev/null || true
    /system/bin/adb shell "echo 3 > /proc/sys/vm/drop_caches" 2>/dev/null || true
    /system/bin/adb shell "rm -rf /data/data/*/code_cache/*" 2>/dev/null || true
    /system/bin/adb shell "find /data/data -maxdepth 2 -name '*.tmp' -type f -delete" 2>/dev/null || true
    /system/bin/adb shell "resetstats" 2>/dev/null || true
    echo "$(TS) INFO Performance optimization complete"
}

# Main function - orchestrates all cleanup
main() {
    echo "$(TS) INFO === pixel_cleanup.sh starting ==="
    
    # Check Chrome status - requires ADB connection
    if is_chrome_running; then
        echo "$(TS) INFO Chrome is running - no cleanup needed at this time"
    else
        echo "$(TS) INFO Chrome is not active - initiating full cleanup..."
        wipe_chrome_data
        wipe_google_account
        wipe_non_google_cache
        clean_artifacts
        optimize_phone
    fi
    
    echo "$(TS) INFO === pixel_cleanup.sh complete ==="
}

# Run main
main "$@"
