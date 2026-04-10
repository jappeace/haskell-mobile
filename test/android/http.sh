#!/usr/bin/env bash
# Android HTTP test: install HTTP demo APK, launch, assert bridge initializes.
#
# This test verifies:
# 1. The HTTP bridge initializes without crashes
# 2. setRoot renders the demo UI
# 3. The "Send Request" button is visible and tappable
# 4. The HTTP request dispatches (http_request logged)
#
# The actual HTTP round-trip is tested by cabal test (desktop stub).
# The emulator test focuses on bridge initialization and JNI wiring.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, HTTP_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

install_apk "$HTTP_APK" || { echo "FAIL: install_apk"; exit 1; }

"$ADB" -s "$EMULATOR_SERIAL" logcat -c
"$ADB" -s "$EMULATOR_SERIAL" shell am start -n "$PACKAGE/$ACTIVITY"

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

# Tap the "Send Request" button to verify it dispatches
"$ADB" -s "$EMULATOR_SERIAL" logcat -c
tap_button "Send Request" || echo "WARNING: could not tap Send Request button"
sleep 5

LOGCAT_FILE2="$WORK_DIR/http_logcat2.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE2" 2>&1 || true

# Verify the HTTP request was dispatched (JNI bridge called)
assert_logcat "$LOGCAT_FILE2" "http_request" "http_request dispatched"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
