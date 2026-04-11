#!/usr/bin/env bash
# iOS HTTP test: install HTTP demo app, launch with --autotest-buttons,
# assert the autotest stub returns success with status 200.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, HTTP_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$HTTP_APP" "http" --autotest-buttons
wait_for_render "http" --autotest-buttons
sleep 5
collect_logs "http"

assert_log "$FULL_LOG" "setRoot" "setRoot"
assert_log "$FULL_LOG" "HTTP demo app registered" "demo app registered"
assert_log "$FULL_LOG" "HTTP response: 200" "HTTP response 200"

cleanup_app

exit $EXIT_CODE
