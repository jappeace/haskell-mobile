#!/usr/bin/env bash
# Android animated-type-change test: widget type change inside Animated wrapper.
#
# Tests that when an Animated wrapper's child changes type (Text→Button),
# the new native node is correctly created and the old one is destroyed.
#
# State0: Animated(Text "ANIM_TEXT")
# State1: Animated(Button "ANIM_BUTTON")
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, ANIMATED_TYPE_CHANGE_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$ANIMATED_TYPE_CHANGE_APK" "animated-type-change"
wait_for_render "animated-type-change"
sleep 5
collect_logcat "atc-initial"

assert_logcat "$LOGCAT_FILE" "Animated screen: ScreenA" "Initial screen is ScreenA"

# Verify ANIM_TEXT visible
DUMP_A="$WORK_DIR/atc_a.xml"
dump_ok=0
for attempt in 1 2 3; do
    if "$ADB" -s "$EMULATOR_SERIAL" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
        "$ADB" -s "$EMULATOR_SERIAL" pull /data/local/tmp/ui.xml "$DUMP_A" 2>/dev/null
        dump_ok=1
        break
    fi
    sleep 5
done

if [ $dump_ok -eq 1 ]; then
    if grep -q 'ANIM_TEXT' "$DUMP_A" 2>/dev/null; then
        echo "PASS: ANIM_TEXT visible on ScreenA"
    else
        echo "FAIL: ANIM_TEXT not visible on ScreenA"
        EXIT_CODE=1
    fi
else
    echo "FAIL: Could not dump view hierarchy (ScreenA)"
    EXIT_CODE=1
fi

# === Switch to ScreenB ===
echo "=== Tapping Switch animated ==="
tap_button "Switch animated" || "$ADB" -s "$EMULATOR_SERIAL" shell input tap 540 100
sleep 5
collect_logcat "atc-after"

assert_logcat "$LOGCAT_FILE" "Animated screen: ScreenB" "Switched to ScreenB"

DUMP_B="$WORK_DIR/atc_b.xml"
dump_ok_b=0
for attempt in 1 2 3; do
    if "$ADB" -s "$EMULATOR_SERIAL" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
        "$ADB" -s "$EMULATOR_SERIAL" pull /data/local/tmp/ui.xml "$DUMP_B" 2>/dev/null
        dump_ok_b=1
        break
    fi
    sleep 5
done

if [ $dump_ok_b -eq 1 ]; then
    echo "=== Post-switch hierarchy ==="
    cat "$DUMP_B"
    echo ""

    # ANIM_BUTTON must be visible
    if grep -q 'ANIM_BUTTON' "$DUMP_B" 2>/dev/null; then
        echo "PASS: ANIM_BUTTON visible on ScreenB"
    else
        echo "FAIL: ANIM_BUTTON not visible on ScreenB"
        EXIT_CODE=1
    fi

    # ANIM_TEXT must be gone
    if grep -q 'ANIM_TEXT' "$DUMP_B" 2>/dev/null; then
        echo "FAIL: ANIM_TEXT still visible after switch (orphaned view)"
        EXIT_CODE=1
    else
        echo "PASS: ANIM_TEXT removed after switch"
    fi
else
    echo "FAIL: Could not dump view hierarchy (ScreenB)"
    EXIT_CODE=1
fi

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
