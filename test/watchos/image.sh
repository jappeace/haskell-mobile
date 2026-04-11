#!/usr/bin/env bash
# watchOS image test: install image app, launch, assert all 3 ImageSource paths are exercised.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, IMAGE_APP, WORK_DIR, LOG_SUBSYSTEM
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$IMAGE_APP" "image"
wait_for_render "image"
sleep 5
collect_logs "image"

# All 3 Image nodes created (type=6)
assert_log "$FULL_LOG" "createNode\(type=6\)" "createNode(type=6) — Image node created"

# Test case 1: ImageResource
assert_log "$FULL_LOG" "setStrProp.*imageResource.*ic_launcher" "ImageResource path set"

# Test case 2: ImageData
assert_log "$FULL_LOG" "setImageData" "ImageData called"

# Test case 3: ImageFile
assert_log "$FULL_LOG" "setStrProp.*imageFile.*/nonexistent" "ImageFile path set"

assert_log "$FULL_LOG" "setRoot" "setRoot"

cleanup_app

exit $EXIT_CODE
