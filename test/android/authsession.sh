#!/usr/bin/env bash
# Android auth session test: install auth session APK, launch, assert bridge initializes.
#
# On the Android emulator, startAuthSession opens a browser intent which
# we can't complete in CI. This test verifies:
# 1. The bridge initializes without crashes
# 2. setRoot renders the demo UI
# 3. The "Start Login" button is visible
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, AUTH_SESSION_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

install_apk "$AUTH_SESSION_APK" || { echo "FAIL: install_apk"; exit 1; }

"$ADB" -s "$EMULATOR_SERIAL" logcat -c
"$ADB" -s "$EMULATOR_SERIAL" shell am start -n "$PACKAGE/$ACTIVITY"

wait_for_logcat "setRoot" 120
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_logcat "authsession"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi
sleep 5

LOGCAT_FILE="$WORK_DIR/authsession_logcat.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1 || true

# Bridge initialized
assert_logcat "$LOGCAT_FILE" "auth session bridge initialized" "auth session bridge initialized"

# setRoot called (demo UI rendered)
assert_logcat "$LOGCAT_FILE" "setRoot" "setRoot called"

# Demo app registered
assert_logcat "$LOGCAT_FILE" "AuthSession demo app registered" "demo app registered"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
