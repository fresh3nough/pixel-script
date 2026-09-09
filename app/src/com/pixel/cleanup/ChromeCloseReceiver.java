package com.pixel.cleanup;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

public class ChromeCloseReceiver extends BroadcastReceiver {
    private static final String TAG = "ChromeCloseReceiver";
    public static final String ACTION_FORCE_CLEANUP = "com.pixel.cleanup.action.FORCE_CLEANUP";
    public static final String ACTION_START_MONITOR = "com.pixel.cleanup.action.START_MONITOR";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) {
            return;
        }
        String action = intent.getAction();
        Log.i(TAG, "onReceive action=" + action);

        if (ACTION_FORCE_CLEANUP.equals(action)) {
            CleanupRunner.runAsync(context.getApplicationContext(), true);
            return;
        }

        Intent svc = new Intent(context, ChromeMonitorService.class);
        svc.setAction(ChromeMonitorService.ACTION_ENSURE);
        try {
            context.startForegroundService(svc);
        } catch (Exception e) {
            Log.e(TAG, "startForegroundService failed, trying startService", e);
            try {
                context.startService(svc);
            } catch (Exception e2) {
                Log.e(TAG, "startService failed", e2);
            }
        }

        if (Intent.ACTION_PACKAGE_CHANGED.equals(action)
                || Intent.ACTION_PACKAGE_RESTARTED.equals(action)
                || Intent.ACTION_PACKAGE_DATA_CLEARED.equals(action)) {
            String pkg = intent.getData() != null ? intent.getData().getSchemeSpecificPart() : null;
            if (pkg != null && pkg.equals(ChromeMonitorService.CHROME_PACKAGE)) {
                Log.i(TAG, "Chrome package event pkg=" + pkg + " action=" + action);
                Intent check = new Intent(context, ChromeMonitorService.class);
                check.setAction(ChromeMonitorService.ACTION_CHECK_NOW);
                try {
                    context.startForegroundService(check);
                } catch (Exception e) {
                    context.startService(check);
                }
            }
        }
    }
}
