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

  testScripts = builtins.path { path = ../test; name = "test-scripts"; };

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
TEST_SCRIPTS="${testScripts}"

# --- Temp working directory ---
WORK_DIR=$(mktemp -d /tmp/haskell-mobile-sim-all-XXXX)
SIM_UDID=""

# Phase result tracking
PHASE1_OK=0
PHASE2_OK=0

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
# PHASE 1 + PHASE 2 — Run test scripts
# ===========================================================================
export SIM_UDID BUNDLE_ID COUNTER_APP SCROLL_APP WORK_DIR

PHASE1_EXIT=0
PHASE2_EXIT=0

echo ""
echo "--- lifecycle ---"
bash "$TEST_SCRIPTS/ios/lifecycle.sh" || PHASE1_EXIT=1
echo "--- ui ---"
bash "$TEST_SCRIPTS/ios/ui.sh"        || PHASE1_EXIT=1
echo "--- buttons ---"
bash "$TEST_SCRIPTS/ios/buttons.sh"   || PHASE1_EXIT=1
echo "--- scroll ---"
bash "$TEST_SCRIPTS/ios/scroll.sh"    || PHASE2_EXIT=1

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
