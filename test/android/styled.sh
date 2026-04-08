#!/usr/bin/env bash
# Android styled test: install counter APK, assert setNumProp calls for fontSize, padding, and gravity.
#
# The counter app wraps its label with Styled (WidgetStyle (Just 16.0) (Just AlignCenter)),
# so rendering must trigger setNumProp for fontSize, padding, and gravity.
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
    dump_logcat "styled"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi
sleep 5

LOGCAT_FILE="$WORK_DIR/styled_logcat.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1 || true

assert_logcat "$LOGCAT_FILE" "setNumProp.*fontSize" "setNumProp dispatched for fontSize"
assert_logcat "$LOGCAT_FILE" "setNumProp.*padding"  "setNumProp dispatched for padding"
assert_logcat "$LOGCAT_FILE" "setNumProp.*gravity"  "setNumProp dispatched for gravity"
assert_logcat "$LOGCAT_FILE" "setStrProp.*color"    "setStrProp dispatched for color (text color)"
assert_logcat "$LOGCAT_FILE" "setStrProp.*bgColor"  "setStrProp dispatched for bgColor (background color)"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
