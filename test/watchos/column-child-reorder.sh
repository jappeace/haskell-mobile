#!/usr/bin/env bash
# watchOS column-child-reorder test: reordering children in a Column.
#
# Tests diffContainer's unstable path (remove-all + re-add-all)
# when children swap positions with mixed widget types.
#
# State0: Column [FIRST, SECOND, THIRD]
# State1: Column [THIRD, SECOND, FIRST]
#
# --autotest fires callbackId=0 (the Reorder button) after 3s.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, LOG_SUBSYSTEM, COLUMN_CHILD_REORDER_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$COLUMN_CHILD_REORDER_APP" "column-child-reorder" --autotest
wait_for_render "column-child-reorder" --autotest

# --autotest fires onUIEvent(0) at +3s — wait for reorder
wait_for_log "$STREAM_LOG" "Reorder state: OrderCBA" 30 || true
sleep 5

collect_logs "column-child-reorder"

assert_log "$FULL_LOG" "setRoot" "setRoot called"
assert_log "$FULL_LOG" "Reorder state: OrderABC" "Initial order is ABC"
assert_log "$FULL_LOG" "Reorder state: OrderCBA" "Reordered to CBA"

cleanup_app

exit $EXIT_CODE
