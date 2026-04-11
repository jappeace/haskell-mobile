#!/usr/bin/env bash
# iOS camera test: install camera app, launch, assert bridge initializes.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, CAMERA_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$CAMERA_APP" "camera" --autotest
wait_for_render "camera" --autotest
sleep 5
collect_logs "camera"

assert_log "$FULL_LOG" "setRoot" "setRoot"
assert_log "$FULL_LOG" "Camera demo app registered" "demo app registered"

cleanup_app

exit $EXIT_CODE
