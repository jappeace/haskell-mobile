#!/usr/bin/env bash
# Android permission test: install permission APK, pre-grant camera, tap button,
# assert that the permission result callback fires.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, PERMISSION_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$PERMISSION_APK" "permission"

# Pre-grant camera permission so the system dialog does not appear
"$ADB" -s "$EMULATOR_SERIAL" shell pm grant "$PACKAGE" android.permission.CAMERA

wait_for_logcat "setRoot" 120 || true
sleep 5

# Tap the "Request Camera" button
tap_button "Request Camera" || { echo "FAIL: could not tap Request Camera"; EXIT_CODE=1; }
sleep 3

collect_logcat "permission"

assert_logcat "$LOGCAT_FILE" "Permission result: PermissionGranted" "permission callback fires with PermissionGranted"
assert_logcat "$LOGCAT_FILE" "permission_request\|PermissionBridge" "permission bridge log present"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
