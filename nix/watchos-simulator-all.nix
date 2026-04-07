# watchOS Simulator combined integration test.
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
#   nix-build nix/watchos-simulator-all.nix -o result-watchos-simulator-all
#   ./result-watchos-simulator-all/bin/test-all-watchos
{ sources ? import ../npins }:
let
  pkgs = import sources.nixpkgs {};

  lib = import ./lib.nix { inherit sources; };

  counterSimApp = import ./watchos-simulator-app.nix { inherit sources; };

  scrollWatchos = import ./watchos.nix {
    inherit sources;
    mainModule = ../test/ScrollDemoMain.hs;
    simulator = true;
  };
  scrollSimApp = lib.mkWatchOSSimulatorApp {
    watchosLib = scrollWatchos;
    watchosSrc = ../watchos;
    name = "haskell-mobile-watchos-scroll-simulator-app";
  };

  textinputWatchos = import ./watchos.nix {
    inherit sources;
    mainModule = ../test/TextInputDemoMain.hs;
    simulator = true;
  };
  textinputSimApp = lib.mkWatchOSSimulatorApp {
    watchosLib = textinputWatchos;
    watchosSrc = ../watchos;
    name = "haskell-mobile-watchos-textinput-simulator-app";
  };

  xcodegen = pkgs.xcodegen;

  testScripts = builtins.path { path = ../test; name = "test-scripts"; };

in pkgs.stdenv.mkDerivation {
  name = "haskell-mobile-watchos-simulator-all-tests";

  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out/bin

    cat > $out/bin/test-all-watchos << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
BUNDLE_ID="me.jappie.haskellmobile.watchkitapp"
SCHEME="HaskellMobile"
DEVICE_TYPE="Apple Watch Series 9 (45mm)"
COUNTER_SHARE_DIR="${counterSimApp}/share/watchos"
SCROLL_SHARE_DIR="${scrollSimApp}/share/watchos"
TEXTINPUT_SHARE_DIR="${textinputSimApp}/share/watchos"
TEST_SCRIPTS="${testScripts}"

# --- Temp working directory ---
WORK_DIR=$(mktemp -d /tmp/haskell-mobile-watchos-sim-all-XXXX)
SIM_UDID=""

# Phase result tracking
PHASE1_OK=0
PHASE2_OK=0
PHASE3_OK=0

cleanup() {
    echo ""
    echo "=== Cleaning up ==="
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

echo "=== watchOS Simulator All-Tests ==="
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

echo "=== Building counter app for watchOS simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk watchsimulator \
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

echo "=== Building scroll demo app for watchOS simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk watchsimulator \
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

# --- Stage and build textinput demo app ---
echo "=== Staging textinput demo app ==="
mkdir -p "$WORK_DIR/textinput/lib" "$WORK_DIR/textinput/include"
cp "$TEXTINPUT_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/textinput/lib/"
cp "$TEXTINPUT_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/textinput/include/"
cp -r "$TEXTINPUT_SHARE_DIR/HaskellMobile" "$WORK_DIR/textinput/"
cp "$TEXTINPUT_SHARE_DIR/project.yml" "$WORK_DIR/textinput/"
chmod -R u+w "$WORK_DIR/textinput"

echo "=== Generating textinput Xcode project ==="
cd "$WORK_DIR/textinput"
${xcodegen}/bin/xcodegen generate

echo "=== Building textinput demo app for watchOS simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk watchsimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/textinput-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

TEXTINPUT_APP=$(find "$WORK_DIR/textinput-build" -name "*.app" -type d | head -1)
if [ -z "$TEXTINPUT_APP" ]; then
    echo "ERROR: Could not find textinput .app bundle"
    exit 1
fi
echo "TextInput app: $TEXTINPUT_APP"

# --- Discover latest watchOS runtime ---
echo "=== Discovering watchOS runtime ==="
RUNTIME=$(xcrun simctl list runtimes -j \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
watchos_runtimes = [r for r in data['runtimes'] if r['platform'] == 'watchOS' and r['isAvailable']]
if not watchos_runtimes:
    print('ERROR: No available watchOS runtimes', file=sys.stderr)
    sys.exit(1)
print(watchos_runtimes[-1]['identifier'])
")
echo "Runtime: $RUNTIME"

# --- Create and boot simulator ---
echo "=== Creating simulator ==="
SIM_UDID=$(xcrun simctl create "test-all-watchos" "$DEVICE_TYPE" "$RUNTIME" \
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
# PHASE 1 + PHASE 2 — Run test scripts
# ===========================================================================
# Log subsystem differs from bundle ID for watchOS (bundle ID has .watchkitapp suffix)
LOG_SUBSYSTEM="me.jappie.haskellmobile"
export SIM_UDID BUNDLE_ID LOG_SUBSYSTEM COUNTER_APP SCROLL_APP TEXTINPUT_APP WORK_DIR

PHASE1_EXIT=0
PHASE2_EXIT=0
PHASE3_EXIT=0

# run_with_retry LABEL COMMAND [ARGS...]
# Runs the command up to 10 times. Succeeds on first pass, fails only if all 10 fail.
run_with_retry() {
    local label="$1"; shift
    local max_attempts=10
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo "[$label] attempt $attempt/$max_attempts"
        if "$@"; then
            echo "[$label] PASSED on attempt $attempt"
            return 0
        fi
        echo "[$label] attempt $attempt FAILED"
        attempt=$((attempt + 1))
        if [ $attempt -le $max_attempts ]; then
            echo "[$label] retrying in 5s..."
            sleep 5
        fi
    done
    echo "[$label] FAILED after $max_attempts attempts"
    return 1
}

echo ""
echo "--- lifecycle ---"
run_with_retry "lifecycle" bash "$TEST_SCRIPTS/watchos/lifecycle.sh" || PHASE1_EXIT=1
echo "--- ui ---"
run_with_retry "ui"        bash "$TEST_SCRIPTS/watchos/ui.sh"        || PHASE1_EXIT=1
echo "--- buttons ---"
run_with_retry "buttons"   bash "$TEST_SCRIPTS/watchos/buttons.sh"   || PHASE1_EXIT=1
echo "--- scroll ---"
run_with_retry "scroll"    bash "$TEST_SCRIPTS/watchos/scroll.sh"    || PHASE2_EXIT=1
echo "--- styled ---"
run_with_retry "styled"    bash "$TEST_SCRIPTS/watchos/styled.sh"    || PHASE1_EXIT=1
echo "--- locale ---"
run_with_retry "locale"    bash "$TEST_SCRIPTS/watchos/locale.sh"    || PHASE1_EXIT=1
echo "--- textinput ---"
run_with_retry "textinput" bash "$TEST_SCRIPTS/watchos/textinput.sh" || PHASE3_EXIT=1

# --- Phase results ---
if [ $PHASE1_EXIT -eq 0 ]; then
    PHASE1_OK=1
    echo ""
    echo "PHASE 1 PASSED"
else
    echo ""
    echo "PHASE 1 FAILED"
fi

if [ $PHASE2_EXIT -eq 0 ]; then
    PHASE2_OK=1
    echo ""
    echo "PHASE 2 PASSED"
else
    echo ""
    echo "PHASE 2 FAILED"
fi

if [ $PHASE3_EXIT -eq 0 ]; then
    PHASE3_OK=1
    echo ""
    echo "PHASE 3 PASSED"
else
    PHASE3_OK=0
    echo ""
    echo "PHASE 3 FAILED"
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

if [ $PHASE3_OK -eq 1 ]; then
    echo "PASS  Phase 3 — TextInput demo app"
else
    echo "FAIL  Phase 3 — TextInput demo app"
    FINAL_EXIT=1
fi

echo ""
if [ $FINAL_EXIT -eq 0 ]; then
    echo "All combined watchOS simulator integration checks passed!"
else
    echo "Some combined watchOS simulator integration checks FAILED."
fi

exit $FINAL_EXIT
SCRIPT

    chmod +x $out/bin/test-all-watchos
  '';

  installPhase = "true";
}
