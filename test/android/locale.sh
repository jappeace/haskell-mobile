#!/usr/bin/env bash
# Android locale test: launch counter app, assert locale detection logs.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, COUNTER_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$COUNTER_APK" "locale"

wait_for_logcat "Locale parsed:" 60
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_logcat "locale"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi

collect_logcat "locale"

assert_logcat "$LOGCAT_FILE" "Locale raw:" "Locale raw tag logged"
assert_logcat "$LOGCAT_FILE" "Locale parsed:" "Locale parsed tag logged"

"$ADB" -s "$EMULATOR_SERIAL" shell am force-stop "$PACKAGE" 2>/dev/null || true
"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
