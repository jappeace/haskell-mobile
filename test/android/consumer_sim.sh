#!/usr/bin/env bash
# Android consumer simulation stress test: install APK with consumer crossDeps,
# launch it repeatedly to catch libndk_translation SIGSEGV (issue #156).
#
# The libndk_translation crash is ASLR-dependent — each cold start of the app
# gets a fresh address space via dlopen, giving a different chance of hitting
# the HandleNoExec fault.  We force-stop and relaunch the app multiple times
# within a single emulator boot to maximise the chance of catching it.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, CONSUMER_SIM_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

ITERATIONS=10
EXIT_CODE=0
SIGSEGV_COUNT=0
PASS_COUNT=0

install_apk "$CONSUMER_SIM_APK" || { echo "FAIL: install_apk"; exit 1; }

for i in $(seq 1 "$ITERATIONS"); do
    echo ""
    echo "=== Consumer sim iteration $i/$ITERATIONS ==="

    # Clear logcat before each launch
    "$ADB" -s "$EMULATOR_SERIAL" logcat -c

    # Launch the app (fresh cold start each time)
    "$ADB" -s "$EMULATOR_SERIAL" shell am start -n "$PACKAGE/$ACTIVITY"

    # Wait for render or fatal crash (60s per iteration, shorter than normal
    # since the APK is already installed)
    wait_for_logcat "setRoot" 60
    WAIT_RC=$?

    # Collect logcat for this iteration
    ITER_LOGCAT="$WORK_DIR/consumer_sim_iter_${i}.txt"
    "$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$ITER_LOGCAT" 2>&1 || true

    if [ "$WAIT_RC" -eq 2 ]; then
        echo "FAIL: iteration $i — FATAL crash detected"
        SIGSEGV_COUNT=$((SIGSEGV_COUNT + 1))
        EXIT_CODE=1
    elif [ "$WAIT_RC" -eq 1 ]; then
        # Timeout — check if it was a silent crash
        if grep -qE "SIGSEGV|Fatal signal 11" "$ITER_LOGCAT" 2>/dev/null; then
            echo "FAIL: iteration $i — SIGSEGV in logcat (missed by wait)"
            SIGSEGV_COUNT=$((SIGSEGV_COUNT + 1))
            EXIT_CODE=1
        else
            echo "WARN: iteration $i — timeout without setRoot (not SIGSEGV)"
        fi
    else
        # setRoot found — verify the app actually works
        if grep -qE "SIGSEGV|Fatal signal 11" "$ITER_LOGCAT" 2>/dev/null; then
            echo "FAIL: iteration $i — SIGSEGV despite setRoot"
            SIGSEGV_COUNT=$((SIGSEGV_COUNT + 1))
            EXIT_CODE=1
        elif grep -q "ConsumerSim demo app registered" "$ITER_LOGCAT" 2>/dev/null; then
            PASS_COUNT=$((PASS_COUNT + 1))
            echo "PASS: iteration $i"
        else
            echo "WARN: iteration $i — setRoot but no registration log"
        fi
    fi

    # Force-stop to get a fresh cold start next iteration.
    # This triggers dlclose + dlopen cycle, giving a new address space.
    "$ADB" -s "$EMULATOR_SERIAL" shell am force-stop "$PACKAGE"
    sleep 2
done

echo ""
echo "=== Consumer sim stress results ==="
echo "Iterations: $ITERATIONS"
echo "Passed:     $PASS_COUNT"
echo "SIGSEGV:    $SIGSEGV_COUNT"
echo ""

if [ "$SIGSEGV_COUNT" -gt 0 ]; then
    echo "FAIL: $SIGSEGV_COUNT/$ITERATIONS iterations hit SIGSEGV (libndk_translation bug)"
fi

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
