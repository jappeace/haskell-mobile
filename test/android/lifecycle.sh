#!/usr/bin/env bash
# Android lifecycle test: install counter app, launch, assert lifecycle events.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, COUNTER_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$COUNTER_APK" "lifecycle"

wait_for_logcat "Android UI bridge initialized" 60
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_logcat "lifecycle"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi

# Dump final logcat for assertions
collect_logcat "lifecycle"

assert_logcat "$LOGCAT_FILE" "Lifecycle: Create" "Lifecycle: Create"
assert_logcat "$LOGCAT_FILE" "Lifecycle: Resume" "Lifecycle: Resume"
assert_logcat "$LOGCAT_FILE" "Android UI bridge initialized" "Android UI bridge initialized"
assert_logcat "$LOGCAT_FILE" "setRoot" "setRoot"
assert_logcat "$LOGCAT_FILE" "setStrProp.*Counter: 0" "setStrProp Counter: 0"
assert_logcat "$LOGCAT_FILE" "setHandler.*click" "setHandler click"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
