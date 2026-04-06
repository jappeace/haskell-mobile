# iOS Simulator combined integration test.
#
# Single simulator session covering all test suites:
#
#   Phase 1 — Counter app (lifecycle + UI rendering + two-button sequence)
#     Verifies: Lifecycle: Create/Resume, setRoot/setStrProp/setHandler,
#               --autotest fires Counter: 1, --autotest-buttons fires full sequence.
#
#   Phase 2 — Scroll demo app
#     Verifies: createNode(type=5), setRoot, Click dispatched: callbackId=0.
#
# One boot + teardown cycle instead of four.
#
# Usage:
#   nix-build nix/simulator-all.nix -o result-simulator-all
#   ./result-simulator-all/bin/test-all-ios
{ sources ? import ../npins }:
let
  pkgs = import sources.nixpkgs {};

  lib = import ./lib.nix { inherit sources; };

  counterSimApp = import ./simulator-app.nix { inherit sources; };

  scrollIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/ScrollDemoMain.hs;
    simulator = true;
  };
  scrollSimApp = lib.mkSimulatorApp {
    iosLib = scrollIos;
    iosSrc = ../ios;
    name = "haskell-mobile-scroll-simulator-app";
  };

  xcodegen = pkgs.xcodegen;

in pkgs.stdenv.mkDerivation {
  name = "haskell-mobile-simulator-all-tests";

  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out/bin

    cat > $out/bin/test-all-ios << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
BUNDLE_ID="me.jappie.haskellmobile"
SCHEME="HaskellMobile"
DEVICE_TYPE="iPhone 16"
COUNTER_SHARE_DIR="${counterSimApp}/share/ios"
SCROLL_SHARE_DIR="${scrollSimApp}/share/ios"

# --- Temp working directory ---
WORK_DIR=$(mktemp -d /tmp/haskell-mobile-sim-all-XXXX)
SIM_UDID=""
LOG_PID=""

# Phase result tracking
PHASE1_OK=0
PHASE2_OK=0

cleanup() {
    echo ""
    echo "=== Cleaning up ==="
    if [ -n "$LOG_PID" ] && kill -0 "$LOG_PID" 2>/dev/null; then
        kill "$LOG_PID" 2>/dev/null || true
    fi
    if [ -n "$SIM_UDID" ]; then
        echo "Shutting down simulator $SIM_UDID"
        xcrun simctl shutdown "$SIM_UDID" 2>/dev/null || true
        echo "Deleting simulator $SIM_UDID"
        xcrun simctl delete "$SIM_UDID" 2>/dev/null || true
    fi
    rm -rf "$WORK_DIR"
    echo "Cleanup done."
}
trap cleanup EXIT

echo "=== iOS Simulator All-Tests ==="
echo "Working directory: $WORK_DIR"

# ===========================================================================
# PHASE 0 — Build both apps + boot simulator
# ===========================================================================
echo ""
echo "============================================================"
echo "PHASE 0: Build apps and boot simulator"
echo "============================================================"

# --- Stage and build counter app ---
echo "=== Staging counter app ==="
mkdir -p "$WORK_DIR/counter/lib" "$WORK_DIR/counter/include"
cp "$COUNTER_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/counter/lib/"
cp "$COUNTER_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/counter/include/"
cp -r "$COUNTER_SHARE_DIR/HaskellMobile" "$WORK_DIR/counter/"
cp "$COUNTER_SHARE_DIR/project.yml" "$WORK_DIR/counter/"
chmod -R u+w "$WORK_DIR/counter"

echo "=== Generating counter Xcode project ==="
cd "$WORK_DIR/counter"
${xcodegen}/bin/xcodegen generate

echo "=== Building counter app for simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/counter-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

COUNTER_APP=$(find "$WORK_DIR/counter-build" -name "*.app" -type d | head -1)
if [ -z "$COUNTER_APP" ]; then
    echo "ERROR: Could not find counter .app bundle"
    exit 1
fi
echo "Counter app: $COUNTER_APP"

# --- Stage and build scroll demo app ---
echo "=== Staging scroll demo app ==="
mkdir -p "$WORK_DIR/scroll/lib" "$WORK_DIR/scroll/include"
cp "$SCROLL_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/scroll/lib/"
cp "$SCROLL_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/scroll/include/"
cp -r "$SCROLL_SHARE_DIR/HaskellMobile" "$WORK_DIR/scroll/"
cp "$SCROLL_SHARE_DIR/project.yml" "$WORK_DIR/scroll/"
chmod -R u+w "$WORK_DIR/scroll"

echo "=== Generating scroll Xcode project ==="
cd "$WORK_DIR/scroll"
${xcodegen}/bin/xcodegen generate

echo "=== Building scroll demo app for simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/scroll-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

SCROLL_APP=$(find "$WORK_DIR/scroll-build" -name "*.app" -type d | head -1)
if [ -z "$SCROLL_APP" ]; then
    echo "ERROR: Could not find scroll .app bundle"
    exit 1
fi
echo "Scroll app: $SCROLL_APP"

# --- Discover latest iOS runtime ---
echo "=== Discovering iOS runtime ==="
RUNTIME=$(xcrun simctl list runtimes -j \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
ios_runtimes = [r for r in data['runtimes'] if r['platform'] == 'iOS' and r['isAvailable']]
if not ios_runtimes:
    print('ERROR: No available iOS runtimes', file=sys.stderr)
    sys.exit(1)
print(ios_runtimes[-1]['identifier'])
")
echo "Runtime: $RUNTIME"

# --- Create and boot simulator ---
echo "=== Creating simulator ==="
SIM_UDID=$(xcrun simctl create "test-all-ios" "$DEVICE_TYPE" "$RUNTIME" \
    | tr -d '[:space:]')

if [ -z "$SIM_UDID" ]; then
    echo "ERROR: Failed to create simulator device"
    exit 1
fi
echo "Simulator UDID: $SIM_UDID"

echo "=== Booting simulator ==="
xcrun simctl boot "$SIM_UDID"

BOOT_TIMEOUT=120
BOOT_ELAPSED=0
STATE="Unknown"
while [ $BOOT_ELAPSED -lt $BOOT_TIMEOUT ]; do
    STATE=$(xcrun simctl list devices -j \
        | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime_devs in data['devices'].values():
    for d in runtime_devs:
        if d['udid'] == '$SIM_UDID':
            print(d['state'])
            sys.exit(0)
print('Unknown')
")
    if [ "$STATE" = "Booted" ]; then
        echo "Simulator booted after ~''${BOOT_ELAPSED}s"
        break
    fi
    sleep 2
    BOOT_ELAPSED=$((BOOT_ELAPSED + 2))
done

if [ "$STATE" != "Booted" ]; then
    echo "ERROR: Simulator failed to boot within ''${BOOT_TIMEOUT}s"
    exit 1
fi

sleep 5

# ===========================================================================
# PHASE 1 — Counter app: lifecycle + UI rendering + two-button sequence
# ===========================================================================
echo ""
echo "============================================================"
echo "PHASE 1: Counter app (lifecycle + UI + buttons)"
echo "============================================================"

PHASE1_EXIT=0

xcrun simctl install "$SIM_UDID" "$COUNTER_APP"
echo "Counter app installed."

LOG_FILE="$WORK_DIR/os_log.txt"

# --- 1a: Lifecycle test ---
echo ""
echo "--- Phase 1a: Lifecycle ---"

> "$LOG_FILE"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"me.jappie.haskellmobile\"" \
    --style compact \
    > "$LOG_FILE" 2>&1 &
LOG_PID=$!
sleep 5

xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

POLL_TIMEOUT=60
POLL_ELAPSED=0
LIFECYCLE_DONE=0
while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
    if grep -q "Lifecycle: Create" "$LOG_FILE" 2>/dev/null && \
       grep -q "Lifecycle: Resume" "$LOG_FILE" 2>/dev/null; then
        LIFECYCLE_DONE=1
        echo "Lifecycle events detected after ~''${POLL_ELAPSED}s"
        break
    fi
    sleep 2
    POLL_ELAPSED=$((POLL_ELAPSED + 2))
done

if [ $LIFECYCLE_DONE -eq 0 ]; then
    echo "WARNING: Lifecycle events not found — retrying with relaunch"
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 3
    > "$LOG_FILE"
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"
    POLL_TIMEOUT=30
    POLL_ELAPSED=0
    while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
        if grep -q "Lifecycle: Create" "$LOG_FILE" 2>/dev/null && \
           grep -q "Lifecycle: Resume" "$LOG_FILE" 2>/dev/null; then
            LIFECYCLE_DONE=1
            echo "Lifecycle events detected after relaunch (~''${POLL_ELAPSED}s)"
            break
        fi
        sleep 2
        POLL_ELAPSED=$((POLL_ELAPSED + 2))
    done
fi

for lifecycle_event in "Lifecycle: Create" "Lifecycle: Resume"; do
    if grep -q "$lifecycle_event" "$LOG_FILE" 2>/dev/null; then
        echo "PASS: $lifecycle_event"
    else
        echo "FAIL: $lifecycle_event not found"
        PHASE1_EXIT=1
    fi
done

for render_check in "setRoot" "setHandler.*click"; do
    if grep -qE "$render_check" "$LOG_FILE" 2>/dev/null; then
        echo "PASS: $render_check in os_log"
    else
        echo "FAIL: $render_check not in os_log"
        PHASE1_EXIT=1
    fi
done

if grep -q 'setStrProp.*Counter:' "$LOG_FILE" 2>/dev/null; then
    echo "PASS: counter label rendered"
else
    echo "FAIL: counter label not found in os_log"
    PHASE1_EXIT=1
fi

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
kill "$LOG_PID" 2>/dev/null || true
LOG_PID=""
sleep 3

# --- 1b: UI rendering (--autotest, expects Counter: 1) ---
echo ""
echo "--- Phase 1b: UI rendering (--autotest) ---"

> "$LOG_FILE"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"me.jappie.haskellmobile\"" \
    --style compact \
    > "$LOG_FILE" 2>&1 &
LOG_PID=$!
sleep 5

xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest

POLL_TIMEOUT=60
POLL_ELAPSED=0
UI_DONE=0
while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
    if grep -q "setStrProp.*Counter: 1" "$LOG_FILE" 2>/dev/null; then
        UI_DONE=1
        echo "Counter: 1 detected after ~''${POLL_ELAPSED}s"
        break
    fi
    sleep 2
    POLL_ELAPSED=$((POLL_ELAPSED + 2))
done

if [ $UI_DONE -eq 0 ]; then
    echo "WARNING: Counter: 1 not found — retrying with relaunch"
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 3
    > "$LOG_FILE"
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest
    POLL_TIMEOUT=60
    POLL_ELAPSED=0
    while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
        if grep -q "setStrProp.*Counter: 1" "$LOG_FILE" 2>/dev/null; then
            UI_DONE=1
            echo "Counter: 1 detected after relaunch (~''${POLL_ELAPSED}s)"
            break
        fi
        sleep 2
        POLL_ELAPSED=$((POLL_ELAPSED + 2))
    done
fi

if grep -q 'setStrProp.*Counter: 1' "$LOG_FILE" 2>/dev/null; then
    echo "PASS: Counter: 1 after --autotest tap"
else
    echo "FAIL: Counter: 1 not found after --autotest"
    PHASE1_EXIT=1
fi

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
kill "$LOG_PID" 2>/dev/null || true
LOG_PID=""
sleep 3

# --- 1c: Two-button sequence (--autotest-buttons) ---
echo ""
echo "--- Phase 1c: Two-button sequence (--autotest-buttons) ---"

> "$LOG_FILE"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "process == \"HaskellMobile\"" \
    --style compact \
    > "$LOG_FILE" 2>&1 &
LOG_PID=$!
sleep 2

xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest-buttons

# Wait for final value Counter: -1
SEQ_TIMEOUT=60
SEQ_ELAPSED=0
SEQ_DONE=0
while [ $SEQ_ELAPSED -lt $SEQ_TIMEOUT ]; do
    if grep -q "setStrProp.*Counter: -1" "$LOG_FILE" 2>/dev/null; then
        SEQ_DONE=1
        echo "Counter: -1 detected after ~''${SEQ_ELAPSED}s"
        break
    fi
    sleep 2
    SEQ_ELAPSED=$((SEQ_ELAPSED + 2))
done

kill "$LOG_PID" 2>/dev/null || true
LOG_PID=""
sleep 1

if [ $SEQ_DONE -eq 0 ]; then
    echo "FAIL: Counter: -1 not seen after ''${SEQ_TIMEOUT}s — autotest-buttons incomplete"
    PHASE1_EXIT=1
else
    # Retrieve full log for reliable assertion
    FULL_LOG="$WORK_DIR/full_log_counter.txt"
    xcrun simctl spawn "$SIM_UDID" log show \
        --predicate "subsystem == \"me.jappie.haskellmobile\"" \
        --style compact \
        --info \
        > "$FULL_LOG" 2>&1 || true

    # Fall back to stream log if log show returned nothing useful
    if ! grep -q "setStrProp" "$FULL_LOG" 2>/dev/null; then
        echo "  'log show' empty, using stream log"
        FULL_LOG="$LOG_FILE"
    fi

    for expected_value in "Counter: 0" "Counter: 1" "Counter: 2" "Counter: -1"; do
        if grep -q "setStrProp.*$expected_value" "$FULL_LOG" 2>/dev/null; then
            echo "PASS: $expected_value in button sequence"
        else
            echo "FAIL: $expected_value not found in button sequence"
            PHASE1_EXIT=1
        fi
    done

    COUNT_1=$(grep -c 'setStrProp.*Counter: 1' "$FULL_LOG" 2>/dev/null || echo "0")
    if [ "$COUNT_1" -ge 2 ]; then
        echo "PASS: Counter: 1 appeared $COUNT_1 times (+ tap and - tap)"
    else
        echo "WARN: Counter: 1 seen $COUNT_1 time(s), expected 2 (log may deduplicate)"
    fi

    COUNT_0=$(grep -c 'setStrProp.*Counter: 0' "$FULL_LOG" 2>/dev/null || echo "0")
    if [ "$COUNT_0" -ge 2 ]; then
        echo "PASS: Counter: 0 appeared $COUNT_0 times (initial and - tap)"
    else
        echo "WARN: Counter: 0 seen $COUNT_0 time(s), expected 2 (log may deduplicate)"
    fi
fi

xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

# --- Phase 1 result ---
if [ $PHASE1_EXIT -eq 0 ]; then
    PHASE1_OK=1
    echo ""
    echo "PHASE 1 PASSED"
else
    echo ""
    echo "PHASE 1 FAILED"
fi

# ===========================================================================
# PHASE 2 — Scroll demo app
# ===========================================================================
echo ""
echo "============================================================"
echo "PHASE 2: Scroll demo app"
echo "============================================================"

PHASE2_EXIT=0

xcrun simctl install "$SIM_UDID" "$SCROLL_APP"
echo "Scroll app installed."

SCROLL_LOG="$WORK_DIR/scroll_log.txt"

> "$SCROLL_LOG"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"me.jappie.haskellmobile\"" \
    --style compact \
    > "$SCROLL_LOG" 2>&1 &
LOG_PID=$!
sleep 5

xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest

# Wait for setRoot
POLL_TIMEOUT=60
POLL_ELAPSED=0
RENDER_DONE=0
while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
    if grep -q "setRoot" "$SCROLL_LOG" 2>/dev/null; then
        RENDER_DONE=1
        echo "Scroll app rendered after ~''${POLL_ELAPSED}s"
        break
    fi
    sleep 2
    POLL_ELAPSED=$((POLL_ELAPSED + 2))
done

if [ $RENDER_DONE -eq 0 ]; then
    echo "WARNING: setRoot not found — retrying with relaunch"
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 3
    > "$SCROLL_LOG"
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest
    POLL_TIMEOUT=60
    POLL_ELAPSED=0
    while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
        if grep -q "setRoot" "$SCROLL_LOG" 2>/dev/null; then
            RENDER_DONE=1
            echo "Scroll app rendered after relaunch (~''${POLL_ELAPSED}s)"
            break
        fi
        sleep 2
        POLL_ELAPSED=$((POLL_ELAPSED + 2))
    done
fi

# Wait for auto-tap click dispatch
POLL_TIMEOUT=30
POLL_ELAPSED=0
CLICK_DONE=0
while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
    if grep -q 'Click dispatched: callbackId=0' "$SCROLL_LOG" 2>/dev/null; then
        CLICK_DONE=1
        echo "Click dispatched after ~''${POLL_ELAPSED}s"
        break
    fi
    sleep 2
    POLL_ELAPSED=$((POLL_ELAPSED + 2))
done

if grep -qE 'createNode\(type=5\)' "$SCROLL_LOG" 2>/dev/null; then
    echo "PASS: createNode(type=5) in os_log"
else
    echo "FAIL: createNode(type=5) not found in os_log"
    PHASE2_EXIT=1
fi

if grep -q 'setRoot' "$SCROLL_LOG" 2>/dev/null; then
    echo "PASS: setRoot in os_log"
else
    echo "FAIL: setRoot not in os_log"
    PHASE2_EXIT=1
fi

if grep -q 'Click dispatched: callbackId=0' "$SCROLL_LOG" 2>/dev/null; then
    echo "PASS: Click dispatched: callbackId=0"
else
    echo "FAIL: Click dispatched: callbackId=0 not found"
    PHASE2_EXIT=1
fi

kill "$LOG_PID" 2>/dev/null || true
LOG_PID=""

xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

# --- Phase 2 result ---
if [ $PHASE2_EXIT -eq 0 ]; then
    PHASE2_OK=1
    echo ""
    echo "PHASE 2 PASSED"
else
    echo ""
    echo "PHASE 2 FAILED"
    echo "=== Filtered scroll log ==="
    grep -i "createNode\|setRoot\|Click dispatched" "$SCROLL_LOG" 2>/dev/null | tail -20 || echo "(no relevant lines)"
fi

# ===========================================================================
# PHASE 3 — Final report
# ===========================================================================
echo ""
echo "============================================================"
echo "FINAL REPORT"
echo "============================================================"

FINAL_EXIT=0

if [ $PHASE1_OK -eq 1 ]; then
    echo "PASS  Phase 1 — Counter app (lifecycle + UI + buttons)"
else
    echo "FAIL  Phase 1 — Counter app (lifecycle + UI + buttons)"
    FINAL_EXIT=1
fi

if [ $PHASE2_OK -eq 1 ]; then
    echo "PASS  Phase 2 — Scroll demo app"
else
    echo "FAIL  Phase 2 — Scroll demo app"
    FINAL_EXIT=1
fi

echo ""
if [ $FINAL_EXIT -eq 0 ]; then
    echo "All combined simulator integration checks passed!"
else
    echo "Some combined simulator integration checks FAILED."
fi

exit $FINAL_EXIT
SCRIPT

    chmod +x $out/bin/test-all-ios
  '';

  installPhase = "true";
}
