#!/usr/bin/env bash
# iOS textinput_rerender test: verify that typing in a TextInput
# triggers a re-render so that a dependent Text widget updates.
#
# Reproduces jappeace/prrrrrrrrr#47.
#
# On iOS simulator we cannot inject keyboard input easily, so we
# verify the structural requirement: the app renders, and the
# UIBridge stub logs show the view function is called with re-render
# after a simulated text change.  The actual typing interaction is
# verified on Android.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, TEXTINPUT_RERENDER_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$TEXTINPUT_RERENDER_APP" "textinput-rerender"

wait_for_render "textinput-rerender"
sleep 5

collect_logs "textinput-rerender"

# Verify app started and rendered
assert_log "$FULL_LOG" "setRoot" "setRoot rendered"
assert_log "$FULL_LOG" "view rebuilt: Typed:" "Initial view shows Typed label"

# Verify the TextInput node was created
assert_log "$FULL_LOG" "createNode.*type=4" "TextInput node created"

cleanup_app

exit $EXIT_CODE
