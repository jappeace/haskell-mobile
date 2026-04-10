#!/usr/bin/env bash
# Android HTTP test: install HTTP demo APK, launch with --ez autotest true,
# assert the autotest stub returns success with status 200.
#
# In autotest mode, the Android HTTP bridge returns a stub 200 response
# without making a real network request (matching the iOS pattern).
#
# This test verifies:
# 1. The HTTP bridge initializes without crashes
# 2. setRoot renders the demo UI
# 3. The "Send Request" button is visible and tappable
# 4. The autotest stub returns HTTP 200
#
# The actual HTTP round-trip is tested by cabal test (desktop stub).
# The emulator test focuses on bridge initialization, JNI wiring, and callback dispatch.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, HTTP_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

install_apk "$HTTP_APK" || { echo "FAIL: install_apk"; exit 1; }

"$ADB" -s "$EMULATOR_SERIAL" logcat -c
"$ADB" -s "$EMULATOR_SERIAL" shell am start -n "$PACKAGE/$ACTIVITY" --ez autotest true

wait_for_logcat "setRoot" 120
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_logcat "http"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi
sleep 5

LOGCAT_FILE="$WORK_DIR/http_logcat.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1 || true

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
