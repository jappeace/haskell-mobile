#!/usr/bin/env bash
# watchOS platform sign-in test: install app, launch with --autotest-buttons,
# assert the autotest stub returns Apple sign-in success.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, PLATFORM_SIGN_IN_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$PLATFORM_SIGN_IN_APP" "platformsignin" --autotest-buttons
wait_for_render "platformsignin" --autotest-buttons
sleep 5
collect_logs "platformsignin"

assert_log "$FULL_LOG" "setRoot" "setRoot"
assert_log "$FULL_LOG" "PlatformSignIn demo app registered" "demo app registered"
assert_log "$FULL_LOG" "PlatformSignIn Apple success:" "Apple sign-in success logged"

cleanup_app

exit $EXIT_CODE
