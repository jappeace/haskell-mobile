#!/usr/bin/env bash
# iOS redraw test: install redraw app, launch,
# verify background thread state updates trigger UI re-renders via requestRedraw.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, REDRAW_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$REDRAW_APP" "redraw"
wait_for_render "redraw"

# Wait for background thread to tick 3 times (3s each = 9s, plus margin)
sleep 15

collect_logs "redraw"
assert_log "$FULL_LOG" "Background tick: 1" "Background tick 1"
assert_log "$FULL_LOG" "Background tick: 2" "Background tick 2"
assert_log "$FULL_LOG" "view rebuilt: count=1" "View rebuilt after background tick 1"
assert_log "$FULL_LOG" "view rebuilt: count=2" "View rebuilt after background tick 2"

cleanup_app

exit $EXIT_CODE
