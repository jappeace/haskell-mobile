#!/usr/bin/env bash
# watchOS mapview test: install mapview app, launch, assert placeholder renders.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, MAPVIEW_APP, WORK_DIR, LOG_SUBSYSTEM
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$MAPVIEW_APP" "mapview"
wait_for_render "mapview"
sleep 5
collect_logs "mapview"

# MapView node created (type=7)
assert_log "$FULL_LOG" "createNode\(type=7\)" "createNode(type=7) — MapView node created"

# Map properties set
assert_log "$FULL_LOG" "setNumProp.*mapLat=" "MapView latitude set"
assert_log "$FULL_LOG" "setNumProp.*mapZoom=" "MapView zoom set"

assert_log "$FULL_LOG" "setRoot" "setRoot"

cleanup_app

exit $EXIT_CODE
