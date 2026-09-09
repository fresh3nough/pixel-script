package com.pixel.cleanup;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.graphics.drawable.Icon;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.PowerManager;
import android.provider.Settings;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

/**
 * Launcher UI: start monitor, force cleanup, pin shortcut, battery exemption.
 */
public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        handleForceIntent(getIntent());


        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = (int) (16 * getResources().getDisplayMetrics().density);
        root.setPadding(pad, pad, pad, pad);

        TextView tv = new TextView(this);
        tv.setText("Pixel Cleanup\n\n"
                + "Monitor starts on boot and after app updates.\n"
                + "Cleanup runs automatically when Chrome closes.\n"
                + "Use Force cleanup for an immediate wipe.");
        root.addView(tv);

        Button start = new Button(this);
        start.setText("Start monitor");
        start.setOnClickListener(v -> {
            startMonitor();
            Toast.makeText(this, "Monitor started", Toast.LENGTH_SHORT).show();
        });
        root.addView(start);

        Button force = new Button(this);
        force.setText("Force cleanup now");
        force.setOnClickListener(v -> {
            CleanupRunner.runAsync(getApplicationContext(), true);
            Toast.makeText(this, "Cleanup started", Toast.LENGTH_SHORT).show();
        });
        root.addView(force);

        Button pin = new Button(this);
        pin.setText("Add Force Cleanup icon to Home");
        pin.setOnClickListener(v -> requestPinnedShortcut());
        root.addView(pin);

        Button batt = new Button(this);
        batt.setText("Disable battery optimization");
        batt.setOnClickListener(v -> requestBatteryExemption());
        root.addView(batt);

        setContentView(root);

        ensureLauncherEnabled();
        publishDynamicShortcuts();
        startMonitor();
        maybePromptBattery();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleForceIntent(intent);
    }

    private void handleForceIntent(Intent in) {
        if (in != null && ChromeCloseReceiver.ACTION_FORCE_CLEANUP.equals(in.getAction())) {
            CleanupRunner.runAsync(getApplicationContext(), true);
            Toast.makeText(this, "Force cleanup started", Toast.LENGTH_SHORT).show();
        }
    }

    private void startMonitor() {
        Intent svc = new Intent(this, ChromeMonitorService.class);
        svc.setAction(ChromeMonitorService.ACTION_ENSURE);
        try {
            startForegroundService(svc);
        } catch (Exception e) {
            startService(svc);
        }
    }

    private void ensureLauncherEnabled() {
        // Keep launcher activity enabled so the icon survives updates.
        PackageManager pm = getPackageManager();
        ComponentName cn = new ComponentName(this, MainActivity.class);
        pm.setComponentEnabledSetting(
                cn,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP);
    }

    private void publishDynamicShortcuts() {
        if (Build.VERSION.SDK_INT < 25) {
            return;
        }
        ShortcutManager sm = getSystemService(ShortcutManager.class);
        if (sm == null) {
            return;
        }
        Intent force = new Intent(this, MainActivity.class);
        force.setAction(ChromeCloseReceiver.ACTION_FORCE_CLEANUP);
        force.setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);

        int iconRes = getResources().getIdentifier("ic_launcher", "drawable", getPackageName());
        ShortcutInfo.Builder b = new ShortcutInfo.Builder(this, "force_cleanup")
                .setShortLabel("Force Clean")
                .setLongLabel("Force Pixel Cleanup")
                .setIntent(force);
        if (iconRes != 0) {
            b.setIcon(Icon.createWithResource(this, iconRes));
        }
        try {
            sm.setDynamicShortcuts(java.util.Collections.singletonList(b.build()));
        } catch (Exception e) {
            // ignore
        }
    }

    private void requestPinnedShortcut() {
        if (Build.VERSION.SDK_INT < 26) {
            Toast.makeText(this, "Pin not supported on this Android version", Toast.LENGTH_SHORT).show();
            return;
        }
        ShortcutManager sm = getSystemService(ShortcutManager.class);
        if (sm == null || !sm.isRequestPinShortcutSupported()) {
            Toast.makeText(this, "Launcher does not support pin shortcuts", Toast.LENGTH_SHORT).show();
            return;
        }
        Intent force = new Intent(this, MainActivity.class);
        force.setAction(ChromeCloseReceiver.ACTION_FORCE_CLEANUP);
        force.setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        int iconRes = getResources().getIdentifier("ic_launcher", "drawable", getPackageName());
        ShortcutInfo.Builder b = new ShortcutInfo.Builder(this, "force_cleanup_pin")
                .setShortLabel("Force Clean")
                .setLongLabel("Force Pixel Cleanup")
                .setIntent(force);
        if (iconRes != 0) {
            b.setIcon(Icon.createWithResource(this, iconRes));
        }
        sm.requestPinShortcut(b.build(), null);
        Toast.makeText(this, "Confirm pin on your home screen", Toast.LENGTH_LONG).show();
    }

    private void requestBatteryExemption() {
        try {
            Intent i = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
            i.setData(Uri.parse("package:" + getPackageName()));
            startActivity(i);
        } catch (Exception e) {
            try {
                Intent i = new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS);
                startActivity(i);
            } catch (Exception e2) {
                Toast.makeText(this, "Open Settings > Apps > Pixel Cleanup > Battery", Toast.LENGTH_LONG).show();
            }
        }
    }

    private void maybePromptBattery() {
        PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
        if (pm == null) {
            return;
        }
        if (pm.isIgnoringBatteryOptimizations(getPackageName())) {
            return;
        }
        new AlertDialog.Builder(this)
                .setTitle("Allow background run")
                .setMessage("To auto-start on reboot and keep monitoring after updates, disable battery optimization for Pixel Cleanup.")
                .setPositiveButton("Allow", (d, w) -> requestBatteryExemption())
                .setNegativeButton("Later", null)
                .show();
    }
}
