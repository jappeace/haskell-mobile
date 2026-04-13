#!/usr/bin/env bash
# Android platform sign-in test: install APK, launch, assert bridge initializes.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, PLATFORM_SIGN_IN_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$PLATFORM_SIGN_IN_APK" "platformsignin"
wait_for_render "platformsignin"
sleep 5
collect_logcat "platformsignin"

# Bridge initialized
assert_logcat "$LOGCAT_FILE" "platform sign-in bridge initialized" "platform sign-in bridge initialized"

# setRoot called (demo UI rendered)
assert_logcat "$LOGCAT_FILE" "setRoot" "setRoot called"

# Demo app registered
assert_logcat "$LOGCAT_FILE" "PlatformSignIn demo app registered" "demo app registered"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
