#!/usr/bin/env bash
# Android integration test for the camera bridge.
# Installs the camera demo APK, launches it, grants camera permission,
# taps "Capture Photo", and verifies no crash occurs.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

# Install APK built from camera demo
install_apk "$CAMERA_APK" || { echo "FAIL: install_apk"; exit 1; }

# Launch the app
"$ADB" -s "$EMULATOR_SERIAL" logcat -c
"$ADB" -s "$EMULATOR_SERIAL" shell am start -n "$PACKAGE/$ACTIVITY"

# Wait for render (setRoot indicates view is rendered)
wait_for_logcat "setRoot" 120 || true
sleep 5

# Grant camera permission
"$ADB" -s "$EMULATOR_SERIAL" shell pm grant "$PACKAGE" android.permission.CAMERA 2>/dev/null || true

# Tap "Start Camera" and verify no crash
tap_button "Start Camera" || { echo "WARNING: could not tap Start Camera"; }
sleep 3

# Tap "Capture Photo" — desktop stub dispatches success immediately
tap_button "Capture Photo" || { echo "WARNING: could not tap Capture Photo"; }
sleep 3

# Tap "Stop Camera"
tap_button "Stop Camera" || { echo "WARNING: could not tap Stop Camera"; }
sleep 2

# Verify expected logs
LOGCAT_FILE="$WORK_DIR/camera_logcat.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1 || true

assert_logcat "$LOGCAT_FILE" "Camera demo app registered" "Camera demo app started"

# Verify no crash
LOGCAT_ERR="$WORK_DIR/camera_logcat_err.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:E' > "$LOGCAT_ERR" 2>&1 || true
if grep -qE "$FATAL_PATTERNS" "$LOGCAT_ERR" 2>/dev/null; then
    echo "FAIL: Fatal crash detected during camera test"
    dump_logcat "camera-error" "$LOGCAT_ERR"
    EXIT_CODE=1
else
    echo "PASS: No crash during camera test"
fi

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
