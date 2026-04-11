#!/usr/bin/env bash
# watchOS BLE test: install BLE app, launch, verify app boots with
# BLE code present without crashing.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, LOG_SUBSYSTEM, BLE_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$BLE_APP" "ble" --autotest
wait_for_render "ble" --autotest
sleep 10
collect_logs "ble"

assert_log "$FULL_LOG" "BLE adapter:" "BLE adapter check logged"
assert_log "$FULL_LOG" "setRoot" "setRoot"

cleanup_app

exit $EXIT_CODE
