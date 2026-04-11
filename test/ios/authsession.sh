#!/usr/bin/env bash
# iOS auth session test: install auth session app, launch with --autotest-buttons,
# assert the autotest stub returns success with the redirect URL.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, AUTH_SESSION_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$AUTH_SESSION_APP" "authsession" --autotest-buttons
wait_for_render "authsession" --autotest-buttons
sleep 5
collect_logs "authsession"

assert_log "$FULL_LOG" "setRoot" "setRoot"
assert_log "$FULL_LOG" "AuthSession demo app registered" "demo app registered"
assert_log "$FULL_LOG" "AuthSession success:" "AuthSession success logged"

cleanup_app

exit $EXIT_CODE
