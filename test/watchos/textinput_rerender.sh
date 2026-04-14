#!/usr/bin/env bash
# watchOS textinput_rerender test: verify app starts and renders.
# Full typing interaction is verified on Android; this just confirms
# the app builds and renders on watchOS.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, TEXTINPUT_RERENDER_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$TEXTINPUT_RERENDER_APP" "textinput-rerender"

wait_for_render "textinput-rerender"
sleep 5

collect_logs "textinput-rerender"

assert_log "$FULL_LOG" "setRoot" "setRoot rendered"
assert_log "$FULL_LOG" "view rebuilt: Typed:" "Initial view shows Typed label"

cleanup_app

exit $EXIT_CODE
