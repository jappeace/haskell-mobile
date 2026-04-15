#!/usr/bin/env bash
# Android column-child-reorder test: reproducer for child reordering in Column.
#
# Tests diffContainer's unstable path when children swap positions.
# Uses mixed widget types (Button/Text) so type changes force replaceNode.
#
# State0: [ITEM_FIRST (Button), ITEM_SECOND (Text), ITEM_THIRD (Text)]
# State1: [ITEM_THIRD (Text), ITEM_SECOND (Text), ITEM_FIRST (Button)]
#
# Verifies visual order by checking uiautomator bounds:
# ITEM_THIRD should appear above (smaller Y) ITEM_FIRST after reorder.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, COLUMN_CHILD_REORDER_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$COLUMN_CHILD_REORDER_APK" "column-child-reorder"
wait_for_render "column-child-reorder"
sleep 5
collect_logcat "ccreorder-initial"

assert_logcat "$LOGCAT_FILE" "Reorder state: OrderABC" "Initial state is OrderABC"

# Verify all items visible initially
DUMP_A="$WORK_DIR/ccreorder_a.xml"
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
    for item in ITEM_FIRST ITEM_SECOND ITEM_THIRD; do
        if grep -q "$item" "$DUMP_A" 2>/dev/null; then
            echo "PASS: $item visible in OrderABC"
        else
            echo "FAIL: $item not visible in OrderABC"
            EXIT_CODE=1
        fi
    done
else
    echo "FAIL: Could not dump view hierarchy (OrderABC)"
    EXIT_CODE=1
fi

# === Reorder ===
echo "=== Tapping Reorder ==="
tap_button "Reorder" || "$ADB" -s "$EMULATOR_SERIAL" shell input tap 540 100
sleep 5
collect_logcat "ccreorder-after"
assert_logcat "$LOGCAT_FILE" "Reorder state: OrderCBA" "Switched to OrderCBA"

DUMP_B="$WORK_DIR/ccreorder_b.xml"
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
    echo "=== Post-reorder hierarchy ==="
    cat "$DUMP_B"
    echo ""

    # All items must still be present
    for item in ITEM_FIRST ITEM_SECOND ITEM_THIRD; do
        if grep -q "$item" "$DUMP_B" 2>/dev/null; then
            echo "PASS: $item visible after reorder"
        else
            echo "FAIL: $item missing after reorder"
            EXIT_CODE=1
        fi
    done

    # Check visual order: ITEM_THIRD should appear BEFORE ITEM_FIRST
    # Extract Y coordinate (top of bounds) for each item
    THIRD_Y=$(grep -o 'text="ITEM_THIRD"[^>]*bounds="\[[0-9]*,\([0-9]*\)' "$DUMP_B" 2>/dev/null | grep -o '[0-9]*$' || echo "")
    FIRST_Y=$(grep -o 'text="ITEM_FIRST"[^>]*bounds="\[[0-9]*,\([0-9]*\)' "$DUMP_B" 2>/dev/null | grep -o '[0-9]*$' || echo "")

    if [ -n "$THIRD_Y" ] && [ -n "$FIRST_Y" ]; then
        if [ "$THIRD_Y" -lt "$FIRST_Y" ]; then
            echo "PASS: ITEM_THIRD (Y=$THIRD_Y) appears above ITEM_FIRST (Y=$FIRST_Y)"
        else
            echo "FAIL: ITEM_THIRD (Y=$THIRD_Y) should appear above ITEM_FIRST (Y=$FIRST_Y) — wrong order"
            EXIT_CODE=1
        fi
    else
        echo "WARN: Could not extract bounds for order check (THIRD_Y=$THIRD_Y, FIRST_Y=$FIRST_Y)"
    fi
else
    echo "FAIL: Could not dump view hierarchy (OrderCBA)"
    EXIT_CODE=1
fi

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
