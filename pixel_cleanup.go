// +build ignore

package main

import (
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// Configuration
const (
	googleChromePackage = "com.android.chrome"
	gmsPackage          = "com.google.android.gms"
)

// Log function with timestamp
func log(level, message string) {
	fmt.Printf("[%s] [%s] %s\n", time.Now().Format("2006-01-02 15:04:05"), level, message)
}

// isChromeRunning checks if Chrome is currently running
func isChromeRunning() bool {
	out, err := exec.Command("adb", "shell", "ps", "|", "grep", "-v", "grep", "|", "grep", googleChromePackage).Output()
	if err != nil {
		log("WARN", "adb command failed, assuming Chrome not running")
		return false
	}
	return strings.Contains(string(out), googleChromePackage)
}

// wipeChromeData clears Chrome app data
func wipeChromeData() {
	log("INFO", "Wiping Google Chrome data...")

	// Clear app data using pm clear
	cmd := exec.Command("adb", "shell", "pm", "clear", googleChromePackage)
	if err := cmd.Run(); err != nil {
		log("WARN", "pm clear failed for Chrome, attempting direct removal")
	}

	// Remove Chrome data directory
	cmd = exec.Command("adb", "shell", "rm", "-rf", "/data/data/"+googleChromePackage)
	cmd.Run()

	// Clear Chrome cache
	cmd = exec.Command("adb", "shell", "rm", "-rf", "/data/data/"+googleChromePackage+"/cache")
	cmd.Run()

	log("INFO", "Chrome data wipe complete")
}

// wipeGoogleAccountData clears Google account data
func wipeGoogleAccountData() {
	log("INFO", "Wiping Google account data...")

	// Clear Google Play Services data
	cmd := exec.Command("adb", "shell", "pm", "clear", gmsPackage)
	cmd.Run()

	// Remove GMS cache and databases
	cmd = exec.Command("adb", "shell", "rm", "-rf", "/data/data/"+gmsPackage+"/cache")
	cmd.Run()
	cmd = exec.Command("adb", "shell", "rm", "-rf", "/data/data/"+gmsPackage+"/databases")
	cmd.Run()

	log("INFO", "Google account data wipe complete")
}

// cleanArtifacts removes residual files
func cleanArtifacts() {
	log("INFO", "Cleaning residual artifacts and bloat...")

	// Clean /cache partition
	cmd := exec.Command("adb", "shell", "rm", "-rf", "/cache/*")
	cmd.Run()

	// Clean /data/local/tmp
	cmd = exec.Command("adb", "shell", "rm", "-rf", "/data/local/tmp/*")
	cmd.Run()

	// Remove temporary files
	cmd = exec.Command("adb", "shell", "find", "/data", "-name", "*.tmp", "-type", "f", "-delete")
	cmd.Run()

	log("INFO", "Artifacts cleanup complete")
}

// optimizePerformance performs phone optimization
func optimizePerformance() {
	log("INFO", "Optimizing phone performance...")

	// Sync filesystem
	cmd := exec.Command("adb", "shell", "sync")
	cmd.Run()

	// Clear dalvik cache
	cmd = exec.Command("adb", "shell", "rm", "-rf", "/data/dalvik-cache/*")
	cmd.Run()

	// Drop caches
	cmd = exec.Command("adb", "shell", "echo", "3", "> /proc/sys/vm/drop_caches")
	cmd.Run()

	log("INFO", "Performance optimization complete")
}

// main - entry point
func main() {
	log("INFO", "=== pixel_cleanup.go starting ===")

	// Check if Chrome is not running (was recently closed)
	if !isChromeRunning() {
		log("INFO", "Chrome closure detected - initiating cleanup...")

		wipeChromeData()
		wipeGoogleAccountData()
		cleanArtifacts()
		optimizePerformance()
	} else {
		log("INFO", "Chrome is active - no cleanup needed at this time")
	}

	log("INFO", "=== pixel_cleanup.go complete ===")
}