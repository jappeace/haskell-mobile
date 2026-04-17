#!/usr/bin/env bash
# Android EaseIn translate animation test.
#
# Installs the ease-in-translate demo APK, launches it, taps
# "Move Text" to trigger an EaseIn animation from (0,0) to (120,80),
# and verifies via logcat that:
#   1. The app started
#   2. The translate position change was logged
#   3. The bridge received setNumProp calls for translateX/translateY
#   4. No fatal crash occurred
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, EASE_IN_TRANSLATE_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$EASE_IN_TRANSLATE_APK" "ease-in-translate"
wait_for_render "ease-in-translate"

sleep 3

# Tap "Move Text" to trigger the EaseIn animation
tap_button "Move Text" || { echo "WARNING: could not tap Move Text"; }

# Wait for animation to complete (400ms duration + settle time)
sleep 3

collect_logcat "ease-in-translate"

# Assert the app started
assert_logcat "$LOGCAT_FILE" "EaseInTranslateDemoMain started" "Demo app started"

# Assert initial position was set on first render
assert_logcat "$LOGCAT_FILE" "setNumProp.*translateX=0.0" "initial translateX=0.0"
assert_logcat "$LOGCAT_FILE" "setNumProp.*translateY=0.0" "initial translateY=0.0"

# Assert position change was logged
assert_logcat "$LOGCAT_FILE" "Moved to position B" "Position B logged"

# Assert the bridge received translate property updates with correct final position
assert_logcat "$LOGCAT_FILE" "setNumProp.*translateX=120.0" "translateX reached 120.0"
assert_logcat "$LOGCAT_FILE" "setNumProp.*translateY=80.0" "translateY reached 80.0"

# Verify no crash
LOGCAT_ERR="$WORK_DIR/ease_in_translate_err.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:E' > "$LOGCAT_ERR" 2>&1 || true
if grep -qE "$FATAL_PATTERNS" "$LOGCAT_ERR" 2>/dev/null; then
    echo "FAIL: Fatal crash detected during ease-in translate test"
    grep -E "$FATAL_PATTERNS" "$LOGCAT_ERR" | tail -10
    EXIT_CODE=1
else
    echo "PASS: No crash during ease-in translate test"
fi

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
