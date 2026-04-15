#!/usr/bin/env bash
# Android styled-type-change test: reproducer for Styled + child type change.
#
# When a Styled wrapper keeps the same style but the inner widget changes
# type (Text→Button), the diff skips applyStyle because newStyle == oldStyle.
# The new native node never gets the styling.
#
# This test verifies:
#   1. ScreenA renders with STYLED_TEXT
#   2. After switch, ScreenB renders with STYLED_BUTTON
#   3. The background color (setBackgroundColor) is applied to the new node
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, STYLED_TYPE_CHANGE_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$STYLED_TYPE_CHANGE_APK" "styled-type-change"
wait_for_render "styled-type-change"
sleep 5
collect_logcat "styled-type-change-initial"

assert_logcat "$LOGCAT_FILE" "Current screen: ScreenA" "Initial screen is ScreenA"
assert_logcat "$LOGCAT_FILE" "setRoot" "setRoot called"

# Verify STYLED_TEXT visible via uiautomator
DUMP_A="$WORK_DIR/stc_a.xml"
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
    if grep -q 'STYLED_TEXT' "$DUMP_A" 2>/dev/null; then
        echo "PASS: STYLED_TEXT visible on ScreenA"
    else
        echo "FAIL: STYLED_TEXT not visible on ScreenA"
        EXIT_CODE=1
    fi
else
    echo "FAIL: Could not dump view hierarchy (pre-switch)"
    EXIT_CODE=1
fi

# Clear logcat before switch so we only see post-switch bridge calls
"$ADB" -s "$EMULATOR_SERIAL" logcat -c 2>/dev/null || true

# === Switch to ScreenB ===
echo "=== Tapping Switch screen ==="
tap_done=0
if [ $dump_ok -eq 1 ]; then
    tap_button "Switch screen" && tap_done=1 || true
fi
if [ $tap_done -eq 0 ]; then
    echo "Using fallback tap at (540, 100)"
    "$ADB" -s "$EMULATOR_SERIAL" shell input tap 540 100
fi
sleep 5

collect_logcat "styled-type-change-after"

assert_logcat "$LOGCAT_FILE" "Current screen: ScreenB" "Switched to ScreenB"

# Dump view hierarchy after switch
DUMP_B="$WORK_DIR/stc_b.xml"
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
    echo "=== Post-switch view hierarchy ==="
    cat "$DUMP_B"
    echo ""
    echo "=== End hierarchy ==="

    # STYLED_BUTTON must be present
    if grep -q 'STYLED_BUTTON' "$DUMP_B" 2>/dev/null; then
        echo "PASS: STYLED_BUTTON visible on ScreenB"
    else
        echo "FAIL: STYLED_BUTTON not visible on ScreenB"
        EXIT_CODE=1
    fi

    # STYLED_TEXT must be gone
    if grep -q 'STYLED_TEXT' "$DUMP_B" 2>/dev/null; then
        echo "FAIL: STYLED_TEXT still visible after switch (orphaned view)"
        EXIT_CODE=1
    else
        echo "PASS: STYLED_TEXT removed after switch"
    fi
else
    echo "FAIL: Could not dump view hierarchy (post-switch)"
    EXIT_CODE=1
fi

# Check if setBackgroundColor was called AFTER the switch.
# If the bug exists, the diff skips applyStyle for the new Button node,
# so no setBackgroundColor call appears in post-switch logcat.
if grep -q 'setBackgroundColor' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: setBackgroundColor called after switch (style applied to new node)"
else
    echo "FAIL: setBackgroundColor NOT called after switch (style NOT applied — BUG)"
    EXIT_CODE=1
fi

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
