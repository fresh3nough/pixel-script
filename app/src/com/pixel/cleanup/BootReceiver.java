package com.pixel.cleanup;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * Starts the Chrome monitor after boot and after this package is replaced (app/OTAs
 * that rewrite the app). directBootAware so locked-boot also works.
 */
public class BootReceiver extends BroadcastReceiver {
    private static final String TAG = "BootReceiver";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent != null ? intent.getAction() : "null";
        Log.i(TAG, "boot/update action=" + action);

        Intent svc = new Intent(context, ChromeMonitorService.class);
        svc.setAction(ChromeMonitorService.ACTION_ENSURE);
        try {
            context.startForegroundService(svc);
        } catch (Exception e) {
            Log.e(TAG, "startForegroundService failed", e);
            try {
                context.startService(svc);
            } catch (Exception e2) {
                Log.e(TAG, "startService failed", e2);
            }
        }

        // Also kick the shell monitor helper if present (ADB-free path).
        try {
            new ProcessBuilder(
                    "/system/bin/sh",
                    "-c",
                    "nohup /system/bin/sh /data/local/tmp/chrome_monitor.sh >/data/local/tmp/chrome_monitor.out 2>&1 &")
                    .start();
        } catch (Exception e) {
            Log.w(TAG, "shell monitor start failed", e);
        }
    }
}
