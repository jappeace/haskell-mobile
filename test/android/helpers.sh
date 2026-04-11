#!/usr/bin/env bash
# Common helper functions for Android emulator test scripts.
# Source this file; do not run directly.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB             — path to adb binary
#   EMULATOR_SERIAL — e.g. emulator-5554
#   PACKAGE         — me.jappie.haskellmobile
#   ACTIVITY        — .MainActivity
#   WORK_DIR        — temp dir for scratch files

# install_apk APK_PATH
# Uninstalls any existing package first (prevents INSTALL_FAILED_UPDATE_INCOMPATIBLE
# when a previous test exited before its cleanup), then installs the given APK
# with up to 3 attempts, 10s delay between retries.
install_apk() {
    local apk_path="$1"
    # Remove leftover package from a previous test that may have exited early.
    # All test APKs share the same package name but may have different signing keys.
    "$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true
    local install_ok=0
    for attempt in 1 2 3; do
        if "$ADB" -s "$EMULATOR_SERIAL" install -t "$apk_path" 2>&1; then
            install_ok=1
            break
        fi
        echo "Install attempt $attempt failed, retrying in 10s..."
        sleep 10
    done
    if [ $install_ok -eq 0 ]; then
        echo "ERROR: Failed to install $apk_path after 3 attempts"
        return 1
    fi
    echo "APK installed: $apk_path"
    return 0
}

# Fatal patterns that indicate the native library failed to load.
# When any of these appear in logcat, further retries are pointless.
FATAL_PATTERNS="UnsatisfiedLinkError|dlopen failed|cannot locate symbol|SIGABRT|SIGSEGV|Fatal signal"

# check_fatal_logcat
# Checks logcat for fatal native-library errors.
# If found, prints the relevant lines and returns 0 (meaning "fatal found").
# Returns 1 if no fatal error detected.
check_fatal_logcat() {
    local logcat_poll="$WORK_DIR/logcat_fatal.txt"
    "$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:E' > "$logcat_poll" 2>&1 || true
    if grep -qE "$FATAL_PATTERNS" "$logcat_poll" 2>/dev/null; then
        echo ""
        echo "=== FATAL: Native library loading error detected ==="
        grep -E "$FATAL_PATTERNS" "$logcat_poll" | tail -20
        echo "=== End fatal logcat ==="
        echo ""
        return 0
    fi
    return 1
}

# dump_logcat LABEL
# Dumps recent logcat errors to stdout for CI visibility.
dump_logcat() {
    local label="$1"
    local logcat_dump="$WORK_DIR/logcat_dump_${label}.txt"
    "$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:W' > "$logcat_dump" 2>&1 || true
    echo ""
    echo "=== Logcat dump ($label) — last 40 warning/error lines ==="
    tail -40 "$logcat_dump"
    echo "=== End logcat dump ==="
    echo ""
}

# wait_for_logcat PATTERN TIMEOUT_SECONDS
# Polls logcat dump every 2s until PATTERN is found.
# Also checks for fatal native-library errors each poll cycle.
# Returns 0 on success, 1 on timeout, 2 on fatal crash detected.
wait_for_logcat() {
    local pattern="$1"
    local timeout_seconds="$2"
    local logcat_poll="$WORK_DIR/logcat_poll.txt"
    local elapsed=0
    while [ $elapsed -lt "$timeout_seconds" ]; do
        "$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$logcat_poll" 2>&1 || true
        if grep -q "$pattern" "$logcat_poll" 2>/dev/null; then
            echo "Found '$pattern' after ~${elapsed}s"
            return 0
        fi
        # Check for fatal errors every 10s to avoid spamming adb
        if [ $((elapsed % 10)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            if check_fatal_logcat; then
                echo "ERROR: Fatal crash detected while waiting for '$pattern'"
                return 2
            fi
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: '$pattern' not found after ${timeout_seconds}s"
    # One last check: was it a crash?
    if check_fatal_logcat; then
        return 2
    fi
    return 1
}

# tap_button BUTTON_TEXT
# Uses uiautomator dump to find a button by text, extract its bounds,
# compute the centre, and issue an adb input tap.
tap_button() {
    local button_text="$1"
    local dump_file="$WORK_DIR/ui_tap.xml"
    local dump_ok=0

    for attempt in 1 2 3; do
        if "$ADB" -s "$EMULATOR_SERIAL" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
            "$ADB" -s "$EMULATOR_SERIAL" pull /data/local/tmp/ui.xml "$dump_file" 2>/dev/null
            dump_ok=1
            break
        fi
        echo "  uiautomator dump attempt $attempt failed, retrying in 5s..."
        sleep 5
    done

    if [ $dump_ok -eq 0 ]; then
        echo "WARNING: Could not dump UI hierarchy for '$button_text' tap"
        return 1
    fi

    local bounds=""
    if [ "$button_text" = "+" ]; then
        bounds=$(grep -o 'text="[+]"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$dump_file" 2>/dev/null \
              || grep -o 'text="\+"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$dump_file" 2>/dev/null \
              || echo "")
    else
        bounds=$(grep -o "text=\"$button_text\"[^>]*bounds=\"\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]\"" "$dump_file" 2>/dev/null \
              || echo "")
    fi

    if [ -z "$bounds" ]; then
        echo "WARNING: Could not find '$button_text' button bounds in UI dump"
        return 1
    fi

    local coords
    coords=$(echo "$bounds" | head -1 | grep -o '\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]')
    local left top right bottom
    left=$(echo "$coords" | sed 's/^\[//;s/,.*//')
    top=$(echo "$coords" | sed 's/^\[[0-9]*,//;s/\].*//')
    right=$(echo "$coords" | sed 's/.*\]\[//;s/,.*//')
    bottom=$(echo "$coords" | sed 's/.*,//;s/\]//')

    local tap_x tap_y
    tap_x=$(( (left + right) / 2 ))
    tap_y=$(( (top + bottom) / 2 ))
    echo "Tapping '$button_text' at ($tap_x, $tap_y)"
    "$ADB" -s "$EMULATOR_SERIAL" shell input tap "$tap_x" "$tap_y"
    return 0
}

# assert_logcat LOGFILE PATTERN LABEL
# Greps LOGFILE for PATTERN, prints PASS/FAIL with LABEL.
# Sets EXIT_CODE=1 on failure (EXIT_CODE must be declared in caller).
assert_logcat() {
    local logfile="$1"
    local pattern="$2"
    local label="$3"
    if grep -q "$pattern" "$logfile" 2>/dev/null; then
        echo "PASS: $label"
    else
        echo "FAIL: $label"
        # shellcheck disable=SC2034  # set for caller
        EXIT_CODE=1
    fi
}

# start_app APK_PATH LABEL [EXTRAS...]
# Installs APK, clears logcat, starts activity with optional intent extras.
start_app() {
    local apk_path="$1"
    local label="$2"
    shift 2

    install_apk "$apk_path" || { echo "FAIL: install_apk"; exit 1; }

    "$ADB" -s "$EMULATOR_SERIAL" logcat -c
    "$ADB" -s "$EMULATOR_SERIAL" shell am start -n "$PACKAGE/$ACTIVITY" "$@"
}

# wait_for_render LABEL
# Waits for "setRoot" (120s). Aborts on fatal crash.
wait_for_render() {
    local label="$1"

    wait_for_logcat "setRoot" 120
    local wait_rc=$?
    if [ $wait_rc -eq 2 ]; then
        dump_logcat "$label"
        echo "FATAL: Native library failed to load — aborting"
        exit 1
    fi
}

# collect_logcat LABEL
# Dumps logcat to file. Sets: LOGCAT_FILE.
collect_logcat() {
    local label="$1"

    LOGCAT_FILE="$WORK_DIR/${label}_logcat.txt"
    "$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1 || true
}
