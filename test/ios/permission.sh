#!/usr/bin/env bash
# iOS permission test: install permission app, pre-grant camera, launch with
# --autotest, assert that the permission result callback fires.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, PERMISSION_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

# Pre-grant camera permission so the system dialog does not appear
xcrun simctl privacy "$SIM_UDID" grant camera "$BUNDLE_ID"

start_app "$PERMISSION_APP" "permission" --autotest
wait_for_render "permission" --autotest

# Wait for autotest tap + permission result
sleep 10

collect_logs "permission"

assert_log "$FULL_LOG" "Permission result: PermissionGranted" "permission callback fires with PermissionGranted"
assert_log "$FULL_LOG" "createNode" "createNode called (app renders)"
assert_log "$FULL_LOG" "setRoot" "setRoot"

cleanup_app

exit $EXIT_CODE
