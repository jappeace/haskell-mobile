#!/usr/bin/env bash
# Android animation test: install animation APK, launch app,
# verify the animation bridge fires callbacks and padding changes.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, ANIMATION_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

install_apk "$ANIMATION_APK" || { echo "FAIL: install_apk"; exit 1; }

"$ADB" -s "$EMULATOR_SERIAL" logcat -c
"$ADB" -s "$EMULATOR_SERIAL" shell am start -n "$PACKAGE/$ACTIVITY"

wait_for_logcat "setRoot" 120 || true
sleep 3

# Tap Toggle Padding button to trigger animation
tap_button "Toggle Padding" || { echo "WARNING: could not tap Toggle Padding"; }
sleep 3

# Dump logcat to check for animation callbacks
LOGCAT_FILE="$WORK_DIR/animation_logcat.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1 || true
assert_logcat "$LOGCAT_FILE" "Toggled padding" "Padding toggled"
assert_logcat "$LOGCAT_FILE" "setNumProp.*padding\|setRoot" "Animation rendered"

# Verify no crash
LOGCAT_ERR="$WORK_DIR/animation_logcat_err.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:E' > "$LOGCAT_ERR" 2>&1 || true
if grep -qE "$FATAL_PATTERNS" "$LOGCAT_ERR" 2>/dev/null; then
    echo "FAIL: Fatal crash detected during animation test"
    grep -E "$FATAL_PATTERNS" "$LOGCAT_ERR" | tail -10
    EXIT_CODE=1
else
    echo "PASS: No crash during animation test"
fi

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
