#!/usr/bin/env bash
# iOS locale test: launch counter app, assert locale detection logs.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, COUNTER_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$COUNTER_APP" "locale"

wait_for_log "$STREAM_LOG" "Locale parsed:" 60
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_ios_log "$STREAM_LOG" "locale"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi

assert_log "$STREAM_LOG" "Locale raw:" "Locale raw tag logged"
assert_log "$STREAM_LOG" "Locale parsed:" "Locale parsed tag logged"

cleanup_app

exit $EXIT_CODE
