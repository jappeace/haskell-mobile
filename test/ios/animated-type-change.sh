#!/usr/bin/env bash
# iOS animated-type-change test: widget type change inside Animated wrapper.
#
# Tests that when an Animated wrapper's child changes type (Text→Button),
# the new native node is correctly created and the old one is destroyed.
#
# State0: Animated(Text "ANIM_TEXT")
# State1: Animated(Button "ANIM_BUTTON")
#
# --autotest fires callbackId=0 (the Switch animated button) after 3s.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, ANIMATED_TYPE_CHANGE_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$ANIMATED_TYPE_CHANGE_APP" "animated-type-change" --autotest
wait_for_render "animated-type-change" --autotest

# --autotest fires onUIEvent(0) at +3s — wait for ScreenB
wait_for_log "$STREAM_LOG" "Animated screen: ScreenB" 30 || true
sleep 5

collect_logs "animated-type-change"

assert_log "$FULL_LOG" "setRoot" "setRoot called"
assert_log "$FULL_LOG" "Animated screen: ScreenA" "Initial screen is ScreenA"
assert_log "$FULL_LOG" "Animated screen: ScreenB" "Switched to ScreenB"

cleanup_app

exit $EXIT_CODE
