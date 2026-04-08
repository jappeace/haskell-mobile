#!/usr/bin/env bash
# Android UI test: install counter app, launch, assert initial render, tap +, assert Counter: 1.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, COUNTER_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

install_apk "$COUNTER_APK" || { echo "FAIL: install_apk"; exit 1; }

"$ADB" -s "$EMULATOR_SERIAL" logcat -c
"$ADB" -s "$EMULATOR_SERIAL" shell am start -n "$PACKAGE/$ACTIVITY"

wait_for_logcat "setRoot" 120
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_logcat "ui"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi
sleep 5

LOGCAT_FILE="$WORK_DIR/ui_logcat.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1 || true

assert_logcat "$LOGCAT_FILE" "setRoot" "initial setRoot"
assert_logcat "$LOGCAT_FILE" "setStrProp.*Counter: 0" "initial Counter: 0"
assert_logcat "$LOGCAT_FILE" "setHandler.*click" "setHandler click"

# Tap + button
tap_button "+" || "$ADB" -s "$EMULATOR_SERIAL" shell input tap 300 600
sleep 5

"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1 || true

assert_logcat "$LOGCAT_FILE" "Click dispatched" "Click dispatched after + tap"
assert_logcat "$LOGCAT_FILE" "setStrProp.*Counter: 1" "Counter: 1 after + tap"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
