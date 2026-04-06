#!/usr/bin/env bash
# Android lifecycle test: install counter app, launch, assert lifecycle events.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, COUNTER_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

install_apk "$COUNTER_APK" || { echo "FAIL: install_apk"; exit 1; }

"$ADB" -s "$EMULATOR_SERIAL" logcat -c
"$ADB" -s "$EMULATOR_SERIAL" shell am start -n "$PACKAGE/$ACTIVITY"

wait_for_logcat "Android UI bridge initialized" 60 || true

# Dump final logcat for assertions
LOGCAT_FILE="$WORK_DIR/lifecycle_logcat.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1

assert_logcat "$LOGCAT_FILE" "Lifecycle: Create" "Lifecycle: Create"
assert_logcat "$LOGCAT_FILE" "Lifecycle: Resume" "Lifecycle: Resume"
assert_logcat "$LOGCAT_FILE" "Android UI bridge initialized" "Android UI bridge initialized"
assert_logcat "$LOGCAT_FILE" "setRoot" "setRoot"
assert_logcat "$LOGCAT_FILE" "setStrProp.*Counter: 0" "setStrProp Counter: 0"
assert_logcat "$LOGCAT_FILE" "setHandler.*click" "setHandler click"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
