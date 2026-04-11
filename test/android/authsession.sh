#!/usr/bin/env bash
# Android auth session test: install auth session APK, launch, assert bridge initializes.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, AUTH_SESSION_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$AUTH_SESSION_APK" "authsession"
wait_for_render "authsession"
sleep 5
collect_logcat "authsession"

# Bridge initialized
assert_logcat "$LOGCAT_FILE" "auth session bridge initialized" "auth session bridge initialized"

# setRoot called (demo UI rendered)
assert_logcat "$LOGCAT_FILE" "setRoot" "setRoot called"

# Demo app registered
assert_logcat "$LOGCAT_FILE" "AuthSession demo app registered" "demo app registered"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
