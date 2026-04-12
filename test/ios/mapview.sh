#!/usr/bin/env bash
# iOS mapview test: install mapview app, launch, assert MKMapView renders.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, MAPVIEW_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$MAPVIEW_APP" "mapview"
wait_for_render "mapview"
sleep 5
collect_logs "mapview"

# MapView node created (type=7)
assert_log "$FULL_LOG" "createNode\(type=7\)" "createNode(type=7) — MKMapView created"
assert_log "$FULL_LOG" "setNumProp.*mapLat=" "MapView latitude set"
assert_log "$FULL_LOG" "setNumProp.*mapLon=" "MapView longitude set"
assert_log "$FULL_LOG" "setNumProp.*mapZoom=" "MapView zoom set"
assert_log "$FULL_LOG" "setHandler.*mapRegionChange" "setHandler registered for region change"
assert_log "$FULL_LOG" "setRoot" "setRoot"

cleanup_app

exit $EXIT_CODE
