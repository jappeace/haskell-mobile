#!/usr/bin/env bash
# Android HTTP test: install HTTP demo APK, launch with --ez autotest true,
# assert the autotest stub returns success with status 200.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, HTTP_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$HTTP_APK" "http" --ez autotest true
wait_for_render "http"
sleep 5
collect_logcat "http"

# Bridge initialized
assert_logcat "$LOGCAT_FILE" "HTTP bridge initialized" "HTTP bridge initialized"

# setRoot called (demo UI rendered)
assert_logcat "$LOGCAT_FILE" "setRoot" "setRoot called"

# Demo app registered
assert_logcat "$LOGCAT_FILE" "HTTP demo app registered" "demo app registered"

# Tap the "Send Request" button to trigger the autotest stub
"$ADB" -s "$EMULATOR_SERIAL" logcat -c
tap_button "Send Request" || echo "WARNING: could not tap Send Request button"
sleep 5

LOGCAT_FILE2="$WORK_DIR/http_logcat2.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE2" 2>&1 || true

# Verify the autotest stub returned HTTP 200
assert_logcat "$LOGCAT_FILE2" "HTTP response: 200" "HTTP response 200 via autotest stub"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
