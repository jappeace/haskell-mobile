#!/usr/bin/env bash
# Android BLE test: install BLE APK, launch app, verify adapter check
# runs and start/stop scan don't crash.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, BLE_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$BLE_APK" "ble"

wait_for_logcat "setRoot" 120 || true
sleep 5

# Verify app rendered (setRoot logged)
collect_logcat "ble"

assert_logcat "$LOGCAT_FILE" "BLE bridge\|BleBridge" "BLE bridge log present"

# Tap Check Adapter button — triggers the BLE adapter FFI check
tap_button "Check Adapter" || { echo "WARNING: could not tap Check Adapter"; }
sleep 3

# Re-dump logcat to capture adapter check result
LOGCAT_FILE1B="$WORK_DIR/ble_logcat1b.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE1B" 2>&1 || true
assert_logcat "$LOGCAT_FILE1B" "BLE adapter:" "BLE adapter check logged"

# Tap Start Scan button — should not crash
tap_button "Start Scan" || { echo "WARNING: could not tap Start Scan"; }
sleep 3

# Tap Stop Scan button — should not crash
tap_button "Stop Scan" || { echo "WARNING: could not tap Stop Scan"; }
sleep 2

# Verify no crash
LOGCAT_FILE2="$WORK_DIR/ble_logcat2.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:E' > "$LOGCAT_FILE2" 2>&1 || true
if grep -qE "$FATAL_PATTERNS" "$LOGCAT_FILE2" 2>/dev/null; then
    echo "FAIL: Fatal crash detected during BLE test"
    # Dump crash context for CI debugging
    grep -E "$FATAL_PATTERNS" "$LOGCAT_FILE2" | tail -10
    EXIT_CODE=1
else
    echo "PASS: No crash during BLE test"
fi

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
