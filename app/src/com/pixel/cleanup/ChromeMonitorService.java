package com.pixel.cleanup;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;

import java.io.BufferedReader;
import java.io.InputStreamReader;

/**
 * Foreground service that polls Chrome PIDs and runs cleanup on running->stopped.
 * Uses pidof/ps so it works without host ADB and without GET_TASKS privileges.
 */
public class ChromeMonitorService extends Service {
    private static final String TAG = "ChromeMonitorService";
    public static final String CHROME_PACKAGE = "com.android.chrome";
    public static final String ACTION_ENSURE = "com.pixel.cleanup.action.ENSURE";
    public static final String ACTION_CHECK_NOW = "com.pixel.cleanup.action.CHECK_NOW";
    private static final String CHANNEL_ID = "pixel_cleanup_monitor";
    private static final int NOTIF_ID = 1001;
    private static final long INTERVAL_MS = 2000L;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private boolean chromeWasRunning = false;
    private boolean started = false;
    private int stableStoppedTicks = 0;

    private final Runnable tick = new Runnable() {
        @Override
        public void run() {
            boolean running = isChromeRunning();
            if (running) {
                stableStoppedTicks = 0;
                if (!chromeWasRunning) {
                    Log.i(TAG, "Chrome started");
                    updateNotification("Chrome open - watching");
                }
                chromeWasRunning = true;
            } else {
                if (chromeWasRunning) {
                    stableStoppedTicks++;
                    // Require two consecutive stopped samples to avoid flapping.
                    if (stableStoppedTicks >= 2) {
                        Log.i(TAG, "Chrome closed edge detected");
                        updateNotification("Chrome closed - cleaning");
                        CleanupRunner.runAsync(getApplicationContext(), false);
                        chromeWasRunning = false;
                        stableStoppedTicks = 0;
                        updateNotification("Monitoring Chrome");
                    }
                } else {
                    stableStoppedTicks = 0;
                }
            }
            handler.postDelayed(this, INTERVAL_MS);
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        createChannel();
        startForeground(NOTIF_ID, buildNotification("Monitoring Chrome"));
        chromeWasRunning = isChromeRunning();
        Log.i(TAG, "onCreate chromeWasRunning=" + chromeWasRunning);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent != null ? intent.getAction() : ACTION_ENSURE;
        Log.i(TAG, "onStartCommand action=" + action);
        startForeground(NOTIF_ID, buildNotification("Monitoring Chrome"));
        if (!started) {
            started = true;
            handler.post(tick);
        }
        if (ACTION_CHECK_NOW.equals(action)) {
            boolean running = isChromeRunning();
            Log.i(TAG, "CHECK_NOW running=" + running + " was=" + chromeWasRunning);
            if (chromeWasRunning && !running) {
                CleanupRunner.runAsync(getApplicationContext(), false);
            }
            chromeWasRunning = running;
        }
        // Keepalive sticky so process restart brings us back after OOM/update.
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        handler.removeCallbacks(tick);
        started = false;
        Log.i(TAG, "onDestroy - requesting restart");
        // Ask system to bring us back quickly.
        Intent svc = new Intent(this, ChromeMonitorService.class);
        svc.setAction(ACTION_ENSURE);
        try {
            startForegroundService(svc);
        } catch (Exception e) {
            Log.w(TAG, "restart request failed", e);
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private boolean isChromeRunning() {
        // pidof is the most reliable without privileged process visibility.
        if (hasPid("com.android.chrome")) {
            return true;
        }
        // Chrome spawns sandboxed helpers; still count parent package name matches.
        return psContainsChrome();
    }

    private boolean hasPid(String name) {
        try {
            Process p = new ProcessBuilder("/system/bin/pidof", name).redirectErrorStream(true).start();
            BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String out = br.readLine();
            int code = p.waitFor();
            boolean ok = code == 0 && out != null && out.trim().length() > 0;
            return ok;
        } catch (Exception e) {
            return false;
        }
    }

    private boolean psContainsChrome() {
        try {
            Process p = new ProcessBuilder("/system/bin/sh", "-c",
                    "ps -A 2>/dev/null | grep -v grep | grep -q 'com.android.chrome'")
                    .redirectErrorStream(true).start();
            return p.waitFor() == 0;
        } catch (Exception e) {
            return false;
        }
    }

    private void createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel ch = new NotificationChannel(
                    CHANNEL_ID,
                    "Pixel Cleanup Monitor",
                    NotificationManager.IMPORTANCE_LOW);
            ch.setDescription("Watches Chrome and runs cleanup on close");
            ch.setShowBadge(false);
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) {
                nm.createNotificationChannel(ch);
            }
        }
    }

    private void updateNotification(String text) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) {
            nm.notify(NOTIF_ID, buildNotification(text));
        }
    }

    private Notification buildNotification(String text) {
        Notification.Builder b;
        if (Build.VERSION.SDK_INT >= 26) {
            b = new Notification.Builder(this, CHANNEL_ID);
        } else {
            b = new Notification.Builder(this);
        }
        int icon = getResources().getIdentifier("ic_launcher", "drawable", getPackageName());
        if (icon == 0) {
            icon = android.R.drawable.ic_menu_manage;
        }
        return b.setContentTitle("Pixel Cleanup")
                .setContentText(text)
                .setSmallIcon(icon)
                .setOngoing(true)
                .build();
    }
}
