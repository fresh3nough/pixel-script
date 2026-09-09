Pixel Cleanup
=============

On-device Google Pixel cleanup that runs when Chrome closes, without requiring
a host ADB connection at runtime.

Components
----------

1. `app/` - Android app `com.pixel.cleanup`
   - `ChromeMonitorService` foreground service polls Chrome process state
   - `ChromeCloseReceiver` listens for package change/restart/data-cleared
   - `BootReceiver` starts monitor on BOOT_COMPLETED, LOCKED_BOOT_COMPLETED,
     USER_UNLOCKED, and MY_PACKAGE_REPLACED (survives app updates)
   - Launcher icon + "Force Clean" shortcut for manual runs
   - Battery optimization prompt so monitoring survives Doze

2. `ondevice/pixel_cleanup_ondevice.sh` - native shell cleanup (no host adb)
   - Preserves one cookie per host when sqlite3 is available
   - Clears Chrome data via `pm clear` (best effort)
   - Clears GMS caches without full account sign-out
   - Artifact cleanup and light performance steps

3. `ondevice/chrome_monitor.sh` - shell companion monitor (ADB-free)

4. `pixel_cleanup.sh` - host-oriented ADB helper (optional)

Runtime behavior
----------------

- No host ADB required after install.
- When Chrome transitions running -> stopped, cleanup runs automatically.
- On reboot, BootReceiver starts the foreground monitor.
- On app update (MY_PACKAGE_REPLACED), monitor restarts.
- Home screen: open "Pixel Cleanup" or pin "Force Clean" shortcut.

Install (one-time, needs ADB once)
----------------------------------

    adb install -r app/build/apk/pixel-cleanup.apk
    adb push ondevice/pixel_cleanup_ondevice.sh /data/local/tmp/pixel_cleanup_ondevice.sh
    adb push ondevice/chrome_monitor.sh /data/local/tmp/chrome_monitor.sh
    adb shell chmod 755 /data/local/tmp/pixel_cleanup_ondevice.sh /data/local/tmp/chrome_monitor.sh
    adb shell dumpsys deviceidle whitelist +com.pixel.cleanup
    adb shell am start -n com.pixel.cleanup/.MainActivity

On the phone
------------

1. Open Pixel Cleanup (launcher icon).
2. Accept battery optimization exemption when prompted.
3. Tap "Add Force Cleanup icon to Home" if you want a one-tap force wipe.
4. Leave the monitor notification running.

Manual force cleanup
--------------------

- App button: Force cleanup now
- Shortcut / intent:

    adb shell am start -a com.pixel.cleanup.action.FORCE_CLEANUP -n com.pixel.cleanup/.MainActivity

- Shell:

    adb shell sh /data/local/tmp/pixel_cleanup_ondevice.sh --force

Logs
----

- `/data/local/tmp/pixel_cleanup.log`
- `/data/local/tmp/chrome_monitor.log`
- `adb logcat -s ChromeMonitorService:I CleanupRunner:I BootReceiver:I ChromeCloseReceiver:I`

Permissions / limits
--------------------

- Full wipe of other apps' `/data/data` requires root or elevated privileges.
- Without root, `pm clear com.android.chrome` works for Chrome; GMS is
  cache-only by design so Google account login is kept.
- Cookie preserve/restore needs `sqlite3` on device and readable cookie DB.

Build APK
---------

Requires JDK 17 and Android SDK build-tools 34 / platform 34.

    cd app
    # see scripts in repo history / build with aapt, javac, d8, apksigner

Security
--------

- Review NON_GOOGLE_APPS before enabling extra package cache wipes.
- This tool deletes browser data; keep backups of anything important.

Contributing
------------

See CONTRIBUTING.md. All commits require DCO sign-off and SSH-signed commits
using anonwurcod@proton.me.
