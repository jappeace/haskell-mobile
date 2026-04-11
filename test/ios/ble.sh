#!/usr/bin/env bash
# iOS BLE test: install BLE app, launch with --autotest, verify adapter
# check runs and app doesn't crash.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, BLE_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$BLE_APP" "ble" --autotest
wait_for_render "ble" --autotest
sleep 10
collect_logs "ble"

assert_log "$FULL_LOG" "BLE adapter:" "BLE adapter check logged"
assert_log "$FULL_LOG" "createNode" "createNode called (app renders)"
assert_log "$FULL_LOG" "setRoot" "setRoot"

cleanup_app

exit $EXIT_CODE
