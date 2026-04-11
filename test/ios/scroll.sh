#!/usr/bin/env bash
# iOS scroll test: install scroll app, launch with --autotest, assert scroll + click events.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, SCROLL_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$SCROLL_APP" "scroll" --autotest
wait_for_render "scroll" --autotest

# Auto-tap fires 3s after render; poll stream log until click appears or 30s timeout
wait_for_log "$STREAM_LOG" "Click dispatched" 30 || true
# Extra buffer so the persistent log store catches up before log show
sleep 5

collect_logs "scroll"

assert_log "$FULL_LOG" 'createNode\(type=5\)' "createNode(type=5)"
assert_log "$FULL_LOG" "setRoot" "setRoot"
assert_log "$FULL_LOG" "Click dispatched: callbackId=0" "Click dispatched: callbackId=0"

cleanup_app

exit $EXIT_CODE
