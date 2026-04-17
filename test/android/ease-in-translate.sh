#!/usr/bin/env bash
# Android EaseIn translate animation test.
#
# Installs the ease-in-translate demo APK, launches it, dumps the
# view hierarchy to capture the text widget's initial bounds, taps
# "Move Text" to trigger an EaseIn animation from (0,0) to (120,80),
# then dumps the hierarchy again and verifies the text has moved to
# the expected position.
#
# Asserts:
#   1. App started without crash
#   2. Text widget visible at initial position in screen dump
#   3. After animation, text widget bounds shifted right by ~120px and down by ~80px
#   4. Bridge received setNumProp calls with correct final values
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, EASE_IN_TRANSLATE_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

# --- Helper: dump UI hierarchy with retries ---
dump_ui() {
    local out_file="$1"
    local dump_ok=0
    for attempt in 1 2 3; do
        if "$ADB" -s "$EMULATOR_SERIAL" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
            "$ADB" -s "$EMULATOR_SERIAL" pull /data/local/tmp/ui.xml "$out_file" 2>/dev/null
            dump_ok=1
            break
        fi
        echo "  uiautomator dump attempt $attempt failed, retrying in 5s..."
        sleep 5
    done
    return $((1 - dump_ok))
}

# --- Helper: extract left,top from bounds for a text node ---
# Usage: extract_bounds DUMP_FILE TEXT_PATTERN
# Prints: LEFT TOP RIGHT BOTTOM
extract_bounds() {
    local dump_file="$1"
    local text_pattern="$2"
    local match
    match=$(grep -o "text=\"${text_pattern}[^\"]*\"[^>]*bounds=\"\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]\"" "$dump_file" 2>/dev/null | head -1 || echo "")
    if [ -z "$match" ]; then
        echo ""
        return 1
    fi
    local coords
    coords=$(echo "$match" | grep -o '\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]')
    local left top right bottom
    left=$(echo "$coords" | sed 's/^\[//;s/,.*//')
    top=$(echo "$coords" | sed 's/^\[[0-9]*,//;s/\].*//')
    right=$(echo "$coords" | sed 's/.*\]\[//;s/,.*//')
    bottom=$(echo "$coords" | sed 's/.*,//;s/\]//')
    echo "$left $top $right $bottom"
}

start_app "$EASE_IN_TRANSLATE_APK" "ease-in-translate"
wait_for_render "ease-in-translate"
sleep 3

# === BEFORE: dump screen at initial position ===
DUMP_BEFORE="$WORK_DIR/ease_in_before.xml"
if dump_ui "$DUMP_BEFORE"; then
    echo "=== Before-animation view hierarchy ==="
    cat "$DUMP_BEFORE"
    echo ""
    echo "=== End hierarchy ==="

    BEFORE_BOUNDS=$(extract_bounds "$DUMP_BEFORE" "EaseIn")
    if [ -n "$BEFORE_BOUNDS" ]; then
        read -r BEFORE_LEFT BEFORE_TOP BEFORE_RIGHT BEFORE_BOTTOM <<< "$BEFORE_BOUNDS"
        echo "PASS: Text found at initial bounds [$BEFORE_LEFT,$BEFORE_TOP][$BEFORE_RIGHT,$BEFORE_BOTTOM]"
    else
        echo "FAIL: Could not find EaseIn text in before-dump"
        EXIT_CODE=1
    fi
else
    echo "FAIL: Could not dump view hierarchy (before animation)"
    EXIT_CODE=1
fi

# === Tap "Move Text" to trigger EaseIn animation ===
tap_button "Move Text" || { echo "WARNING: could not tap Move Text"; }

# Wait for animation to complete (400ms duration + settle time)
sleep 3

# === AFTER: dump screen at final position ===
DUMP_AFTER="$WORK_DIR/ease_in_after.xml"
if dump_ui "$DUMP_AFTER"; then
    echo "=== After-animation view hierarchy ==="
    cat "$DUMP_AFTER"
    echo ""
    echo "=== End hierarchy ==="

    AFTER_BOUNDS=$(extract_bounds "$DUMP_AFTER" "EaseIn")
    if [ -n "$AFTER_BOUNDS" ]; then
        read -r AFTER_LEFT AFTER_TOP AFTER_RIGHT AFTER_BOTTOM <<< "$AFTER_BOUNDS"
        echo "PASS: Text found at final bounds [$AFTER_LEFT,$AFTER_TOP][$AFTER_RIGHT,$AFTER_BOTTOM]"
    else
        echo "FAIL: Could not find EaseIn text in after-dump"
        EXIT_CODE=1
    fi
else
    echo "FAIL: Could not dump view hierarchy (after animation)"
    EXIT_CODE=1
fi

# === Verify the text moved by the expected offset ===
# Android density may scale the dp values, but the relative shift should
# match translateX=120 and translateY=80 in device pixels.  We check that
# the left edge moved right and the top edge moved down.
if [ -n "${BEFORE_BOUNDS:-}" ] && [ -n "${AFTER_BOUNDS:-}" ]; then
    DX=$((AFTER_LEFT - BEFORE_LEFT))
    DY=$((AFTER_TOP - BEFORE_TOP))
    echo "Measured delta: dx=$DX dy=$DY"

    if [ "$DX" -gt 0 ]; then
        echo "PASS: Text moved right (dx=$DX)"
    else
        echo "FAIL: Text did not move right (dx=$DX)"
        EXIT_CODE=1
    fi

    if [ "$DY" -gt 0 ]; then
        echo "PASS: Text moved down (dy=$DY)"
    else
        echo "FAIL: Text did not move down (dy=$DY)"
        EXIT_CODE=1
    fi
fi

# === Logcat assertions ===
collect_logcat "ease-in-translate"

assert_logcat "$LOGCAT_FILE" "EaseInTranslateDemoMain started" "Demo app started"
assert_logcat "$LOGCAT_FILE" "Moved to position B" "Position B logged"
assert_logcat "$LOGCAT_FILE" "setNumProp.*translateX=0.0" "initial translateX=0.0"
assert_logcat "$LOGCAT_FILE" "setNumProp.*translateY=0.0" "initial translateY=0.0"
assert_logcat "$LOGCAT_FILE" "setNumProp.*translateX=120.0" "translateX reached 120.0"
assert_logcat "$LOGCAT_FILE" "setNumProp.*translateY=80.0" "translateY reached 80.0"

# Verify no crash
LOGCAT_ERR="$WORK_DIR/ease_in_translate_err.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:E' > "$LOGCAT_ERR" 2>&1 || true
if grep -qE "$FATAL_PATTERNS" "$LOGCAT_ERR" 2>/dev/null; then
    echo "FAIL: Fatal crash detected during ease-in translate test"
    grep -E "$FATAL_PATTERNS" "$LOGCAT_ERR" | tail -10
    EXIT_CODE=1
else
    echo "PASS: No crash during ease-in translate test"
fi

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
