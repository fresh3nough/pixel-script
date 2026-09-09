pixel_cleanup.sh - Test Cases
=============================

Test: Chrome Data Wipe
----------------------
1. Start the script when Chrome is running
2. Verify no cleanup occurs (Chrome data should remain intact)
3. Close Chrome browser
4. Re-run the script
5. Verify Chrome data directory is cleared
6. Verify Chrome cache is empty
7. Verify Chrome browser data is wiped

Test: Google Account Data Wipe
------------------------------
1. Start the script with Chrome closed
2. Verify Google Account data is wiped
3. Check that /data/data/com.google.android.gms cache is cleared
4. Check that GMS databases are removed

Test: Non-Google App Cache Cleanup
----------------------------------
1. Set NON_GOOGLE_APPS variable to specific package names
2. Install test apps if needed
3. Run the script
4. Verify cache directories for specified apps are cleared
5. Verify app data is preserved (pm clear removes all data, use with caution)

Test: Artifacts and Bloat Cleanup
---------------------------------
1. Create test temporary files in /cache, /data/local/tmp
2. Run the script
3. Verify test files are removed
4. Verify system-critical files are not deleted

Test: Performance Optimization
------------------------------
1. Run the script
2. Verify sync completes successfully
3. Verify dalvik-cache is cleared (or optimized)
4. Check that drop_caches command executes without error

Test: Script Safety and Exit Codes
-----------------------------------
1. Run the script with no arguments
2. Verify exit code is 0 on success
3. Verify error handling for ADB connection failures
4. Verify the script does not wipe data when Chrome is actively running

Usage Notes
-----------

- Test these cases on a real Google Pixel device with ADB access
- Review and adjust the NON_GOOGLE_APPS variable before running
- The script is designed to run periodically or on Chrome closure events
- Backup important data before running, as this wipes Google-related data