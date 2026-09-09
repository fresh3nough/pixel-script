Testing
=======

Prerequisites
-------------

- Pixel device authorized over ADB for install/debug only
- `com.pixel.cleanup` installed
- Scripts present under `/data/local/tmp/`

Test Case 1: Chrome close triggers cleanup
------------------------------------------

Steps:
1. `adb shell am start -n com.pixel.cleanup/.MainActivity`
2. `adb shell monkey -p com.android.chrome -c android.intent.category.LAUNCHER 1`
3. Wait until `pidof com.android.chrome` returns a PID
4. `adb shell am force-stop com.android.chrome`
5. Wait 8 seconds

Expected:
- `/data/local/tmp/chrome_monitor.log` contains `Chrome closed transition`
- `/data/local/tmp/pixel_cleanup.log` contains `cleanup complete`
- Exit path reports cleanup exit=0

Test Case 2: Force cleanup intent
---------------------------------

Steps:
1. `adb shell am start -a com.pixel.cleanup.action.FORCE_CLEANUP -n com.pixel.cleanup/.MainActivity`
2. Inspect logcat `CleanupRunner`

Expected:
- CleanupRunner logs wipe steps and `cleanup exit=0`

Test Case 3: Boot receiver registration
---------------------------------------

Steps:
1. `adb shell dumpsys package com.pixel.cleanup | grep BOOT_COMPLETED`

Expected:
- BootReceiver registered for BOOT_COMPLETED, LOCKED_BOOT_COMPLETED,
  MY_PACKAGE_REPLACED, USER_UNLOCKED

Test Case 4: Launcher icon
--------------------------

Steps:
1. `adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER com.pixel.cleanup`

Expected:
- Resolves `com.pixel.cleanup/.MainActivity`

Test Case 5: Service sticky after start
---------------------------------------

Steps:
1. Start MainActivity
2. `adb shell dumpsys activity services com.pixel.cleanup`

Expected:
- `ChromeMonitorService` isForeground=true

Test Case 6: Update persistence (MY_PACKAGE_REPLACED)
-----------------------------------------------------

Steps:
1. Reinstall APK with `adb install -r`
2. Confirm service running after open or after broadcast

Expected:
- Monitor service present; app remains launchable

Test Case 7: Cookie preserve path (optional)
--------------------------------------------

Steps:
1. Use Chrome while logged into a site
2. Trigger cleanup with sqlite3 available and readable cookie DB

Expected:
- Log lines `preserved cookie rows` and restore attempts

Notes
-----

- `drop_caches` may fail without root; treat as soft failure.
- App UID may not write shell-owned logs until log file mode is 666.
