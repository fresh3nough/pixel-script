package com.pixel.cleanup;

import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class CleanupRunner {
    private static final String TAG = "CleanupRunner";
    public static final String SCRIPT_PATH = "/data/local/tmp/pixel_cleanup_ondevice.sh";
    private static final ExecutorService EXEC = Executors.newSingleThreadExecutor();

    private CleanupRunner() {
    }

    public static void runAsync(final android.content.Context context, final boolean force) {
        EXEC.execute(new Runnable() {
            @Override
            public void run() {
                runBlocking(force);
            }
        });
    }

    public static int runBlocking(boolean force) {
        File script = new File(SCRIPT_PATH);
        if (!script.exists()) {
            Log.e(TAG, "missing script " + SCRIPT_PATH);
            return 127;
        }
        try {
            ProcessBuilder pb;
            if (force) {
                pb = new ProcessBuilder("/system/bin/sh", SCRIPT_PATH, "--force");
            } else {
                pb = new ProcessBuilder("/system/bin/sh", SCRIPT_PATH);
            }
            pb.redirectErrorStream(true);
            Process p = pb.start();
            BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line;
            while ((line = br.readLine()) != null) {
                Log.i(TAG, line);
            }
            int code = p.waitFor();
            Log.i(TAG, "cleanup exit=" + code);
            return code;
        } catch (Exception e) {
            Log.e(TAG, "cleanup failed", e);
            return 1;
        }
    }
}
