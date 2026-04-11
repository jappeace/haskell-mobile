#!/usr/bin/env bash
# watchOS textinput test: install textinput app, launch, assert it renders without crashing.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, TEXTINPUT_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$TEXTINPUT_APP" "textinput"
wait_for_render "textinput"
sleep 5
collect_logs "textinput"

assert_log "$FULL_LOG" "createNode" "createNode called (app renders without crashing)"
assert_log "$FULL_LOG" "setRoot" "setRoot"

cleanup_app

exit $EXIT_CODE
