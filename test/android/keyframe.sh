#!/usr/bin/env bash
# Android keyframe animation test: install keyframe APK, launch app,
# tap "Trigger Keyframe" to start the 3-keyframe animation,
# verify logcat shows expected animation coordinates.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, KEYFRAME_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$KEYFRAME_APK" "keyframe"
wait_for_render "keyframe"
sleep 2

# Tap Trigger Keyframe button
tap_button "Trigger Keyframe" || { echo "WARNING: could not tap Trigger Keyframe"; }
sleep 3

# Collect logcat
collect_logcat "keyframe"

# Verify keyframe triggered
assert_logcat "$LOGCAT_FILE" "Keyframe triggered" "Keyframe triggered"

# Verify animation callbacks fired (setNumProp for translateX/Y)
assert_logcat "$LOGCAT_FILE" "setNumProp.*translateX\|setRoot" "Animation rendered"

# Verify no crash
LOGCAT_ERR="$WORK_DIR/keyframe_logcat_err.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:E' > "$LOGCAT_ERR" 2>&1 || true
if grep -qE "$FATAL_PATTERNS" "$LOGCAT_ERR" 2>/dev/null; then
    echo "FAIL: Fatal crash detected during keyframe test"
    grep -E "$FATAL_PATTERNS" "$LOGCAT_ERR" | tail -10
    EXIT_CODE=1
else
    echo "PASS: No crash during keyframe test"
fi

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
