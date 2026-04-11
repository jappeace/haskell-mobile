#!/usr/bin/env bash
# watchOS location test: install location app, launch, verify app boots
# with location code present without crashing.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, LOG_SUBSYSTEM, LOCATION_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$LOCATION_APP" "location" --autotest
wait_for_render "location" --autotest
sleep 10
collect_logs "location"

assert_log "$FULL_LOG" "setRoot" "setRoot"

cleanup_app

exit $EXIT_CODE
