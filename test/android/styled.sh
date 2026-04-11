#!/usr/bin/env bash
# Android styled test: install counter APK, assert setNumProp calls for fontSize, padding, and gravity.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, COUNTER_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$COUNTER_APK" "styled"
wait_for_render "styled"
sleep 5
collect_logcat "styled"

assert_logcat "$LOGCAT_FILE" "setNumProp.*fontSize" "setNumProp dispatched for fontSize"
assert_logcat "$LOGCAT_FILE" "setNumProp.*padding"  "setNumProp dispatched for padding"
assert_logcat "$LOGCAT_FILE" "setNumProp.*gravity"  "setNumProp dispatched for gravity"
assert_logcat "$LOGCAT_FILE" "setStrProp.*color"    "setStrProp dispatched for color (text color)"
assert_logcat "$LOGCAT_FILE" "setStrProp.*bgColor"  "setStrProp dispatched for bgColor (background color)"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
