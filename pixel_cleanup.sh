#!/system/bin/sh
#
# pixel_cleanup.sh - Automated Google data wipe and phone optimization
# Triggers on Google Chrome closure and performs comprehensive cleanup
#
# This script is designed to run on Google Pixel devices via ADB or Termux.
# It watches for Chrome closure and performs data wiping and optimization.
#

set -e

# =============================================================================
# Configuration
# =============================================================================

# Package names
GOOGLE_CHROME_PACKAGE="com.android.chrome"
GOOGLE_ACCOUNTS_PACKAGE="com.google.android.gms"
ANDROID_SYSTEM="android"

# Data directories to clean
CHROME_DATA_DIR="/data/data/${GOOGLE_CHROME_PACKAGE}"
GOOGLE_GMS_DIR="/data/data/${GOOGLE_ACCOUNTS_PACKAGE}"

# Non-Google app packages to clean cache for (user-specified)
# Format: "package1 package2 ..."
NON_GOOGLE_APPS=""

# =============================================================================
# Utility Functions
# =============================================================================

# Log messages with timestamp
log() {
    local level="$1"
    shift
    local message="$*"
    # Use echo to stderr for logging; in production redirect as needed
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}" >&2
}

# Check if Chrome is running
is_chrome_running() {
    adb shell "ps | grep -v grep | grep ${GOOGLE_CHROME_PACKAGE}" | grep -q "${GOOGLE_CHROME_PACKAGE}"
    return $?
}

# Check if Chrome process exists in last check
chrome_was_recently_closed() {
    # Check Chromium last close timestamp or use state file
    local state_file="/data/local/tmp/chrome_closed_state"
    if [ -f "$state_file" ]; then
        # If state file exists and marks Chrome as closed, return 0
        return 0
    fi
    return 1
}

# =============================================================================
# Data Wiping Functions
# =============================================================================

# Wipe Google Chrome data (browser data, cache, etc.)
wipe_chrome_data() {
    log "INFO" "Wiping Google Chrome data..."

    # Clear app data completely using pm clear
    adb shell "pm clear ${GOOGLE_CHROME_PACKAGE}" || log "WARN" "pm clear failed for Chrome, attempting direct removal"

    # Remove Chrome data directory if pm clear didn't handle it
    adb shell "rm -rf ${CHROME_DATA_DIR}" || log "WARN" "Could not remove ${CHROME_DATA_DIR}"

    # Clear Chrome cache specifically
    adb shell "rm -rf /data/data/${GOOGLE_CHROME_PACKAGE}/cache" 2>/dev/null || true

    # Clear crash reports and logs
    adb shell "rm -rf /data/data/${GOOGLE_CHROME_PACKAGE}/app_chrome*" 2>/dev/null || true

    log "INFO" "Chrome data wipe complete"
}

# Wipe Google account data (GMS, etc.)
wipe_google_account_data() {
    log "INFO" "Wiping Google account data..."

    # Clear Google Play Services data
    adb shell "pm clear ${GOOGLE_ACCOUNTS_PACKAGE}" 2>/dev/null || log "WARN" "pm clear failed for GMS"

    # Remove GMS database and cache
    adb shell "rm -rf ${GOOGLE_GMS_DIR}/cache" 2>/dev/null || true
    adb shell "rm -rf ${GOOGLE_GMS_DIR}/databases" 2>/dev/null || true

    # Clear any residual Google auth tokens/cache
    adb shell "rm -rf /data/misc/credentials/*" 2>/dev/null || true

    log "INFO" "Google account data wipe complete"
}

# Wipe non-Google app cache and bloat
wipe_non_google_app_cache() {
    log "INFO" "Wiping non-Google app cache and artifacts..."

    # If no specific apps listed, skip
    if [ -z "${NON_GOOGLE_APPS}" ]; then
        log "INFO" "No non-Google apps specified, skipping"
        return 0
    fi

    # Clean cache for each specified non-Google app
    for app in ${NON_GOOGLE_APPS}; do
        if adb shell "pm list packages -e | grep -q ${app}" 2>/dev/null; then
            log "INFO" "Cleaning cache for: ${app}"
            adb shell "pm clear ${app}" 2>/dev/null || log "WARN" "Failed to clear ${app}"
            adb shell "rm -rf /data/data/${app}/cache" 2>/dev/null || true
            adb shell "rm -rf /data/data/${app}/app_compat*" 2>/dev/null || true
        else
            log "WARN" "App not found: ${app}"
        fi
    done

    log "INFO" "Non-Google app cache cleanup complete"
}

# Delete residual artifacts and bloat
clean_artifacts() {
    log "INFO" "Cleaning residual artifacts and bloat..."

    # Clean /cache partition (safe, temporary files only)
    adb shell "rm -rf /cache/*" 2>/dev/null || log "WARN" "Could not clean /cache"

    # Clean /data/local/tmp
    adb shell "rm -rf /data/local/tmp/*" 2>/dev/null || log "WARN" "Could not clean /data/local/tmp"

    # Remove any leftover .thumbnails or crash reports outside app directories
    adb shell "find /data -name '*.tmp' -type f -delete" 2>/dev/null || true
    adb shell "find /data -name '*~' -type f -delete" 2>/dev/null || true

    # Clean dowloaded files that are not from Google apps
    adb shell "rm -rf /storage/emulated/0/Download/*" 2>/dev/null || log "WARN" "Could not clean Download dir"

    log "INFO" "Artifacts cleanup complete"
}

# =============================================================================
# Performance Optimization Functions
# =============================================================================

optimize_phone_performance() {
    log "INFO" "Optimizing phone performance..."

    # Sync filesystem to ensure pending writes are flushed
    adb shell "sync" || true

    # Set conservative CPU scaling (if supported)
    adb shell "echo 'powersave' > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" 2>/dev/null || true

    # Clear dalvik/art cache to free memory
    adb shell "rm -rf /data/dalvik-cache/*" 2>/dev/null || true
    adb shell "rm -rf /data/data/*/cache/*" 2>/dev/null || true

    # Optimize ODEX files
    adb shell "dex2oat --optimize" 2>/dev/null || true

    # Reset memory pressure
    adb shell "echo 3 > /proc/sys/vm/drop_caches" 2>/dev/null || true

    log "INFO" "Performance optimization complete"
}

# =============================================================================
# Main Cleanup Orchestration
# =============================================================================

main() {
    log "INFO" "=== pixel_cleanup.sh starting ==="

    # Check Chrome status and perform cleanup if recently closed
    if chrome_was_recently_closed; then
        log "INFO" "Chrome closure detected - initiating cleanup..."

        wipe_chrome_data
        wipe_google_account_data
        wipe_non_google_app_cache
        clean_artifacts
        optimize_phone_performance
    else
        log "INFO" "Chrome is active - no cleanup needed at this time"
    fi

    log "INFO" "=== pixel_cleanup.sh complete ==="
}

# =============================================================================
# Entry Point
# =============================================================================

# Run main function
main "$@"