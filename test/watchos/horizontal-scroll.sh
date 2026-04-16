#!/usr/bin/env bash
# watchOS horizontal scroll test: install horizontal-scroll app, launch with --autotest,
# assert horizontal scroll view + click events.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, HORIZONTAL_SCROLL_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$HORIZONTAL_SCROLL_APP" "horizontal-scroll" --autotest
wait_for_render "horizontal-scroll" --autotest

# Auto-tap fires 3s after render; poll stream log until click appears or 30s timeout
wait_for_log "$STREAM_LOG" "Click dispatched" 30 || true
# Extra buffer so the persistent log store catches up before log show
sleep 5

collect_logs "horizontal-scroll"

assert_log "$FULL_LOG" 'createNode\(type=10\)' "createNode(type=10)"
assert_log "$FULL_LOG" "setRoot" "setRoot"
assert_log "$FULL_LOG" "Click dispatched: callbackId=0" "Click dispatched: callbackId=0"

cleanup_app

exit $EXIT_CODE
