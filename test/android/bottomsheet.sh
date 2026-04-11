#!/usr/bin/env bash
# Android bottom sheet test: install APK, tap Show Actions, tap Edit item,
# and assert that the callback fires correctly.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, BOTTOM_SHEET_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$BOTTOM_SHEET_APK" "bottomsheet"

wait_for_logcat "setRoot" 120 || true
sleep 5

# Tap the "Show Actions" button
tap_button "Show Actions" || { echo "FAIL: could not tap Show Actions"; EXIT_CODE=1; }
sleep 3

# Tap "Edit" in the bottom sheet
tap_button "Edit" || { echo "FAIL: could not tap Edit"; EXIT_CODE=1; }
sleep 3

collect_logcat "bottomsheet"

assert_logcat "$LOGCAT_FILE" "BottomSheet result: BottomSheetItemSelected 0" "bottom sheet callback fires with BottomSheetItemSelected 0"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
