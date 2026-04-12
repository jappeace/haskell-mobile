#!/usr/bin/env bash
# Android mapview test: install mapview APK, assert MapView placeholder renders.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, MAPVIEW_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$MAPVIEW_APK" "mapview"
wait_for_render "mapview"
sleep 5
collect_logcat "mapview"

# MapView node created (type=7)
assert_logcat "$LOGCAT_FILE" "createNode.*type=7" "createNode(type=7) MapView node"

# Latitude property set
assert_logcat "$LOGCAT_FILE" "setNumProp.*mapProp=5" "MapView latitude set"

# Longitude property set
assert_logcat "$LOGCAT_FILE" "setNumProp.*mapProp=6" "MapView longitude set"

# Zoom property set
assert_logcat "$LOGCAT_FILE" "setNumProp.*mapProp=7" "MapView zoom set"

# Region change handler registered
assert_logcat "$LOGCAT_FILE" "setHandler.*mapRegionChange" "setHandler registered for region change"

# setRoot called
assert_logcat "$LOGCAT_FILE" "setRoot" "setRoot called"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
