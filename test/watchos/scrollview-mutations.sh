#!/usr/bin/env bash
# watchOS scrollview-mutations test: add/remove/reorder children inside a ScrollView.
#
# Tests the inner LinearLayout/StackView wrapper handling.
# Cycles: [A,B,C] → [A,B,C,D] → [A,C,D] → [D,C,A]
#
# --autotest fires callbackId=0 (the Advance button) after 3s.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, LOG_SUBSYSTEM, SCROLLVIEW_MUTATIONS_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$SCROLLVIEW_MUTATIONS_APP" "scrollview-mutations" --autotest
wait_for_render "scrollview-mutations" --autotest

# --autotest fires onUIEvent(0) at +3s — wait for SV1
wait_for_log "$STREAM_LOG" "ScrollView state: SV1" 30 || true
sleep 5

collect_logs "scrollview-mutations"

assert_log "$FULL_LOG" "setRoot" "setRoot called"
assert_log "$FULL_LOG" "ScrollView state: SV0" "Initial state is SV0"
assert_log "$FULL_LOG" "ScrollView state: SV1" "Advanced to SV1"

cleanup_app

exit $EXIT_CODE
