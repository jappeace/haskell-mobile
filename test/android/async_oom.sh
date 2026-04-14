#!/usr/bin/env bash
# Android async-OOM reproducer (issue #163).
#
# The async package causes the .so to balloon during dlopen, OOM-killing
# the process before any Haskell code executes.  This test installs the
# APK, launches it, and asserts that the app starts successfully.
# Expected result: FAIL (the app never starts — proving the bug).
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, ASYNC_OOM_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$ASYNC_OOM_APK" "async_oom"

# Wait for the platformLog output that proves Haskell code ran.
# Expected: this never arrives because the process is OOM-killed during
# .so loading.
wait_for_logcat "async loaded" 60
WAIT_RC=$?

# Always dump logcat for diagnostics — this is a reproducer, we want
# to see exactly what happens.
echo ""
echo "=== async_oom: full logcat dump ==="
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:W' 2>&1 | tail -80
echo "=== end async_oom logcat ==="
echo ""

# Also check process status
echo "=== async_oom: process status ==="
"$ADB" -s "$EMULATOR_SERIAL" shell "ps -A 2>/dev/null | grep -i jappie || echo 'Process not found (likely killed)'"
echo "=== end process status ==="
echo ""

if [ $WAIT_RC -eq 2 ]; then
    echo "FATAL: Native library failed to load (expected for async OOM reproducer)"
    EXIT_CODE=1
fi
if [ $WAIT_RC -eq 1 ]; then
    echo "FAIL: Timed out waiting for 'async loaded' (app likely OOM-killed)"

    # Check logcat for OOM indicators
    LOGCAT_OOM="$WORK_DIR/async_oom_logcat.txt"
    "$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:W' > "$LOGCAT_OOM" 2>&1 || true
    if grep -qE "oom-kill|Out of memory|lowmemorykiller|Killing.*adj|am_kill|am_proc_died" "$LOGCAT_OOM" 2>/dev/null; then
        echo ""
        echo "=== OOM/kill indicators found ==="
        grep -E "oom-kill|Out of memory|lowmemorykiller|Killing.*adj|am_kill|am_proc_died" "$LOGCAT_OOM" | tail -20
        echo "=== end OOM indicators ==="
    else
        echo "No OOM-kill indicators found in logcat (process may have been silently killed)"
    fi
    EXIT_CODE=1
fi

# Collect final logcat
collect_logcat "async_oom"

# Assert the app actually started (this is the key assertion — it should FAIL)
assert_logcat "$LOGCAT_FILE" "async loaded" "async package loaded successfully"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
