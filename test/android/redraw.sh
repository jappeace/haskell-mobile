#!/usr/bin/env bash
# Android redraw test: install redraw APK, launch app,
# verify background thread state updates trigger UI re-renders via requestRedraw.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, REDRAW_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$REDRAW_APK" "redraw"
wait_for_render "redraw"

# Wait for background thread to tick 3 times (3s each = 9s, plus margin)
sleep 15

collect_logcat "redraw"
assert_logcat "$LOGCAT_FILE" "Background tick: 1" "Background tick 1"
assert_logcat "$LOGCAT_FILE" "Background tick: 2" "Background tick 2"
assert_logcat "$LOGCAT_FILE" "view rebuilt: count=1" "View rebuilt after background tick 1"
assert_logcat "$LOGCAT_FILE" "view rebuilt: count=2" "View rebuilt after background tick 2"

# Verify no crash
LOGCAT_ERR="$WORK_DIR/redraw_logcat_err.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:E' > "$LOGCAT_ERR" 2>&1 || true
if grep -qE "$FATAL_PATTERNS" "$LOGCAT_ERR" 2>/dev/null; then
    echo "FAIL: Fatal crash detected during redraw test"
    grep -E "$FATAL_PATTERNS" "$LOGCAT_ERR" | tail -10
    EXIT_CODE=1
else
    echo "PASS: No crash during redraw test"
fi

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
