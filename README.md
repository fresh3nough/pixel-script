pixel_cleanup.sh
================

Automated Google data wipe and phone optimization script for Google Pixel devices.

Overview
--------

This script performs comprehensive cleanup when Google Chrome is closed:
- Wipes Google Chrome browser data, cache, and artifacts
- Wipes Google account data (Google Play Services, GMS)
- Cleans cache for non-Google applications
- Removes residual artifacts and bloat
- Optimizes phone performance

Prerequisites
-------------

- Google Pixel device with ADB access
- ADB server running
- SSH key configured for GitHub (anonwurcod@proton.me)

Configuration
-------------

Edit the following variables at the top of the script:

- NON_GOOGLE_APPS: Space-separated list of package names to also clean cache for
  (e.g., "com.facebook.katana com.spotify.music")

Usage
-----

Via ADB:
    adb shell /data/local/tmp/pixel_cleanup.sh

Or via Termux on the device itself.

The script checks if Chrome was recently closed and performs the full cleanup
sequence only when Chrome closure is detected.

Components
----------

1. wipe_chrome_data  - Clears Chrome app data, cache, and browser data
2. wipe_google_account_data  - Clears Google Play Services and account data
3. wipe_non_google_app_cache  - Cleans cache for specified non-Google apps
4. clean_artifacts  - Removes residual files from /cache, /data/local/tmp, etc.
5. optimize_phone_performance  - Performance optimization (sync, cpu governor, dalvik-cache)

Logging
-------

All output is logged to stderr with timestamps. To redirect log output:

    adb shell /data/local/tmp/pixel_cleanup.sh > cleanup.log 2>&1

Security Notes
--------------

- This script wipes all Google-related data and application caches
- Review the NON_GOOGLE_APPS list before use to avoid unintended data loss
- The /cache partition cleanup removes temporary system files only
- Run with caution on devices with important data that cannot be recovered

Contributing
------------

See CONTRIBUTING.md for contribution guidelines and test cases.