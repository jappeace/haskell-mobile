#!/usr/bin/env bash
# Android styled test: install counter APK, assert setNumProp calls for fontSize + padding.
#
# The counter app wraps its label with Styled (WidgetStyle (Just 24.0) (Just 16.0)),
# so rendering must trigger setNumProp for both properties.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, COUNTER_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

install_apk "$COUNTER_APK" || { echo "FAIL: install_apk"; exit 1; }

"$ADB" -s "$EMULATOR_SERIAL" logcat -c
"$ADB" -s "$EMULATOR_SERIAL" shell am start -n "$PACKAGE/$ACTIVITY"

wait_for_logcat "setRoot" 120 || true
sleep 5

LOGCAT_FILE="$WORK_DIR/styled_logcat.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1

assert_logcat "$LOGCAT_FILE" "setNumProp.*fontSize" "setNumProp dispatched for fontSize"
assert_logcat "$LOGCAT_FILE" "setNumProp.*padding"  "setNumProp dispatched for padding"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
