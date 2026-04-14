#!/usr/bin/env bash
# Android consumer simulation test: install APK with consumer crossDeps,
# launch, and assert the app starts without SIGSEGV.
#
# This test targets issue #156: consumer apps (with real Hackage dependencies
# in crossDeps + extraJniBridge files) crash with SIGSEGV at startup on
# x86_64 Android emulators running ARM binary translation, even though
# hatter's own (empty-crossDeps) test APKs pass.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, CONSUMER_SIM_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$CONSUMER_SIM_APK" "consumer_sim"
wait_for_render "consumer_sim"
sleep 5
collect_logcat "consumer_sim"

# setRoot called (UI rendered successfully)
assert_logcat "$LOGCAT_FILE" "setRoot" "setRoot called"

# Demo app registered (Haskell main executed)
assert_logcat "$LOGCAT_FILE" "ConsumerSim demo app registered" "consumer sim demo app registered"

# hashable sanity check (consumer dep actually loaded and ran)
assert_logcat "$LOGCAT_FILE" "hashable sanity:" "hashable dependency functional"

# Explicit SIGSEGV check — if the app crashed, the above assertions would
# already have failed (wait_for_render aborts on fatal signals), but this
# makes the failure reason crystal clear in CI output.
if grep -qE "SIGSEGV|Fatal signal 11" "$LOGCAT_FILE" 2>/dev/null; then
    echo "FAIL: SIGSEGV detected in logcat"
    EXIT_CODE=1
fi

# Verify app process is still alive
if ! "$ADB" -s "$EMULATOR_SERIAL" shell pidof "$PACKAGE" >/dev/null 2>&1; then
    echo "FAIL: app process not running (likely crashed)"
    EXIT_CODE=1
else
    echo "PASS: app process still running"
fi

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
