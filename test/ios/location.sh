#!/usr/bin/env bash
# iOS location test: install location app, launch with --autotest, verify
# location bridge initialises and app doesn't crash.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, LOCATION_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

# Set simulated location before launch
xcrun simctl location "$SIM_UDID" set 52.37,4.90 2>/dev/null || true

start_app "$LOCATION_APP" "location" --autotest
wait_for_render "location" --autotest
sleep 10
collect_logs "location"

assert_log "$FULL_LOG" "Location demo app registered" "Location demo app started"
assert_log "$FULL_LOG" "createNode" "createNode called (app renders)"
assert_log "$FULL_LOG" "setRoot" "setRoot"

cleanup_app

exit $EXIT_CODE
