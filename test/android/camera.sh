#!/usr/bin/env bash
# Android camera test: install camera APK, launch, assert bridge initializes.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, CAMERA_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$CAMERA_APK" "camera"
wait_for_render "camera"
sleep 5
collect_logcat "camera"

# setRoot called (demo UI rendered)
assert_logcat "$LOGCAT_FILE" "setRoot" "setRoot called"

# Demo app registered
assert_logcat "$LOGCAT_FILE" "Camera demo app registered" "demo app registered"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
