#!/usr/bin/env bash
# Android dialog test: install APK, tap Show Alert, tap OK in the AlertDialog,
# then tap Show Confirm, tap No, and assert that the callbacks fire correctly.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, DIALOG_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$DIALOG_APK" "dialog"

wait_for_logcat "setRoot" 120 || true
sleep 5

# Tap the "Show Alert" button
tap_button "Show Alert" || { echo "FAIL: could not tap Show Alert"; EXIT_CODE=1; }
sleep 3

# Tap "OK" in the AlertDialog
tap_button "OK" || { echo "FAIL: could not tap OK"; EXIT_CODE=1; }
sleep 3

collect_logcat "dialog"

assert_logcat "$LOGCAT_FILE" "Dialog alert result: DialogButton1" "alert callback fires with DialogButton1"

# Clear logcat for confirm test
"$ADB" -s "$EMULATOR_SERIAL" logcat -c
sleep 2

# Tap "Show Confirm" button
tap_button "Show Confirm" || { echo "FAIL: could not tap Show Confirm"; EXIT_CODE=1; }
sleep 3

# Tap "No" in the confirm dialog (button 2)
tap_button "No" || { echo "FAIL: could not tap No"; EXIT_CODE=1; }
sleep 3

LOGCAT_FILE2="$WORK_DIR/dialog_logcat2.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE2" 2>&1

assert_logcat "$LOGCAT_FILE2" "Dialog confirm result: DialogButton2" "confirm callback fires with DialogButton2"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
