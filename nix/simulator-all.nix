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

  textinputIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/TextInputDemoMain.hs;
    simulator = true;
  };
  textinputSimApp = lib.mkSimulatorApp {
    iosLib = textinputIos;
    iosSrc = ../ios;
    name = "haskell-mobile-textinput-simulator-app";
  };

  permissionIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/PermissionDemoMain.hs;
    simulator = true;
  };
  permissionSimApp = lib.mkSimulatorApp {
    iosLib = permissionIos;
    iosSrc = ../ios;
    name = "haskell-mobile-permission-simulator-app";
  };

  secureStorageIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/SecureStorageDemoMain.hs;
    simulator = true;
  };
  secureStorageSimApp = lib.mkSimulatorApp {
    iosLib = secureStorageIos;
    iosSrc = ../ios;
    name = "haskell-mobile-securestorage-simulator-app";
  };

  imageIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/ImageDemoMain.hs;
    simulator = true;
  };
  imageSimApp = lib.mkSimulatorApp {
    iosLib = imageIos;
    iosSrc = ../ios;
    name = "haskell-mobile-image-simulator-app";
  };

  nodepoolIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/NodePoolTestMain.hs;
    simulator = true;
  };
  nodepoolSimApp = lib.mkSimulatorApp {
    iosLib = nodepoolIos;
    iosSrc = ../ios;
    name = "haskell-mobile-nodepool-simulator-app";
    dynamicNodePool = true;
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
TEXTINPUT_SHARE_DIR="${textinputSimApp}/share/ios"
PERMISSION_SHARE_DIR="${permissionSimApp}/share/ios"
SECURE_STORAGE_SHARE_DIR="${secureStorageSimApp}/share/ios"
IMAGE_SHARE_DIR="${imageSimApp}/share/ios"
NODEPOOL_SHARE_DIR="${nodepoolSimApp}/share/ios"
TEST_SCRIPTS="${testScripts}"

# --- Temp working directory ---
WORK_DIR=$(mktemp -d /tmp/haskell-mobile-sim-all-XXXX)
SIM_UDID=""

# Phase result tracking
PHASE1_OK=0
PHASE2_OK=0
PHASE3_OK=0
PHASE4_OK=0
PHASE5_OK=0
PHASE6_OK=0
PHASE7_OK=0

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
cp "$COUNTER_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/counter/include/"
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
cp "$SCROLL_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/scroll/include/"
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

# --- Stage and build textinput demo app ---
echo "=== Staging textinput demo app ==="
mkdir -p "$WORK_DIR/textinput/lib" "$WORK_DIR/textinput/include"
cp "$TEXTINPUT_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/textinput/lib/"
cp "$TEXTINPUT_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/textinput/include/"
cp -r "$TEXTINPUT_SHARE_DIR/HaskellMobile" "$WORK_DIR/textinput/"
cp "$TEXTINPUT_SHARE_DIR/project.yml" "$WORK_DIR/textinput/"
chmod -R u+w "$WORK_DIR/textinput"

echo "=== Generating textinput Xcode project ==="
cd "$WORK_DIR/textinput"
${xcodegen}/bin/xcodegen generate

echo "=== Building textinput demo app for simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
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

# --- Stage and build permission demo app ---
echo "=== Staging permission demo app ==="
mkdir -p "$WORK_DIR/permission/lib" "$WORK_DIR/permission/include"
cp "$PERMISSION_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/permission/lib/"
cp "$PERMISSION_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/permission/include/"
cp -r "$PERMISSION_SHARE_DIR/HaskellMobile" "$WORK_DIR/permission/"
cp "$PERMISSION_SHARE_DIR/project.yml" "$WORK_DIR/permission/"
chmod -R u+w "$WORK_DIR/permission"

echo "=== Generating permission Xcode project ==="
cd "$WORK_DIR/permission"
${xcodegen}/bin/xcodegen generate

echo "=== Building permission demo app for simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/permission-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

PERMISSION_APP=$(find "$WORK_DIR/permission-build" -name "*.app" -type d | head -1)
if [ -z "$PERMISSION_APP" ]; then
    echo "ERROR: Could not find permission .app bundle"
    exit 1
fi
echo "Permission app: $PERMISSION_APP"

# --- Stage and build securestorage demo app ---
echo "=== Staging securestorage demo app ==="
mkdir -p "$WORK_DIR/securestorage/lib" "$WORK_DIR/securestorage/include"
cp "$SECURE_STORAGE_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/securestorage/lib/"
cp "$SECURE_STORAGE_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/securestorage/include/"
cp -r "$SECURE_STORAGE_SHARE_DIR/HaskellMobile" "$WORK_DIR/securestorage/"
cp "$SECURE_STORAGE_SHARE_DIR/project.yml" "$WORK_DIR/securestorage/"
chmod -R u+w "$WORK_DIR/securestorage"

echo "=== Generating securestorage Xcode project ==="
cd "$WORK_DIR/securestorage"
${xcodegen}/bin/xcodegen generate

echo "=== Building securestorage demo app for simulator (ad-hoc signed for Keychain entitlements) ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/securestorage-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=YES \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

SECURE_STORAGE_APP=$(find "$WORK_DIR/securestorage-build" -name "*.app" -type d | head -1)
if [ -z "$SECURE_STORAGE_APP" ]; then
    echo "ERROR: Could not find securestorage .app bundle"
    exit 1
fi
echo "SecureStorage app: $SECURE_STORAGE_APP"

# --- Stage and build image test app ---
echo "=== Staging image test app ==="
mkdir -p "$WORK_DIR/image/lib" "$WORK_DIR/image/include"
cp "$IMAGE_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/image/lib/"
cp "$IMAGE_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/image/include/"
cp -r "$IMAGE_SHARE_DIR/HaskellMobile" "$WORK_DIR/image/"
cp "$IMAGE_SHARE_DIR/project.yml" "$WORK_DIR/image/"
chmod -R u+w "$WORK_DIR/image"

echo "=== Generating image Xcode project ==="
cd "$WORK_DIR/image"
${xcodegen}/bin/xcodegen generate

echo "=== Building image test app for simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/image-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

IMAGE_APP=$(find "$WORK_DIR/image-build" -name "*.app" -type d | head -1)
if [ -z "$IMAGE_APP" ]; then
    echo "ERROR: Could not find image .app bundle"
    exit 1
fi
echo "Image app: $IMAGE_APP"

# --- Stage and build node-pool test app ---
echo "=== Staging node-pool test app ==="
mkdir -p "$WORK_DIR/nodepool/lib" "$WORK_DIR/nodepool/include"
cp "$NODEPOOL_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/nodepool/lib/"
cp "$NODEPOOL_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/nodepool/include/"
cp -r "$NODEPOOL_SHARE_DIR/HaskellMobile" "$WORK_DIR/nodepool/"
cp "$NODEPOOL_SHARE_DIR/project.yml" "$WORK_DIR/nodepool/"
chmod -R u+w "$WORK_DIR/nodepool"

echo "=== Generating node-pool Xcode project ==="
cd "$WORK_DIR/nodepool"
${xcodegen}/bin/xcodegen generate

echo "=== Building node-pool test app for simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/nodepool-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

NODEPOOL_APP=$(find "$WORK_DIR/nodepool-build" -name "*.app" -type d | head -1)
if [ -z "$NODEPOOL_APP" ]; then
    echo "ERROR: Could not find node-pool .app bundle"
    exit 1
fi
echo "NodePool app: $NODEPOOL_APP"

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
export SIM_UDID BUNDLE_ID COUNTER_APP SCROLL_APP TEXTINPUT_APP PERMISSION_APP SECURE_STORAGE_APP IMAGE_APP NODEPOOL_APP WORK_DIR

PHASE1_EXIT=0
PHASE2_EXIT=0
PHASE3_EXIT=0
PHASE4_EXIT=0
PHASE5_EXIT=0
PHASE6_EXIT=0
PHASE7_EXIT=0

# run_with_retry LABEL COMMAND [ARGS...]
# Runs the command up to 10 times. Succeeds on first pass, fails only if all 10 fail.
# If the command outputs "FATAL:", retrying is pointless (e.g. native library failed
# to load), so we stop immediately and report the error.
run_with_retry() {
    local label="$1"; shift
    local max_attempts=10
    local attempt=1
    local output_file="$WORK_DIR/retry_''${label}.log"
    while [ $attempt -le $max_attempts ]; do
        echo "[$label] attempt $attempt/$max_attempts"
        if "$@" 2>&1 | tee "$output_file"; then
            echo "[$label] PASSED on attempt $attempt"
            return 0
        fi
        if grep -q "^FATAL:" "$output_file" 2>/dev/null; then
            echo "[$label] FATAL error detected — not retrying"
            return 1
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
run_with_retry "lifecycle" bash "$TEST_SCRIPTS/ios/lifecycle.sh" || PHASE1_EXIT=1
echo "--- ui ---"
run_with_retry "ui"        bash "$TEST_SCRIPTS/ios/ui.sh"        || PHASE1_EXIT=1
echo "--- buttons ---"
run_with_retry "buttons"   bash "$TEST_SCRIPTS/ios/buttons.sh"   || PHASE1_EXIT=1
echo "--- scroll ---"
run_with_retry "scroll"    bash "$TEST_SCRIPTS/ios/scroll.sh"    || PHASE2_EXIT=1
echo "--- styled ---"
run_with_retry "styled"    bash "$TEST_SCRIPTS/ios/styled.sh"    || PHASE1_EXIT=1
echo "--- locale ---"
run_with_retry "locale"    bash "$TEST_SCRIPTS/ios/locale.sh"    || PHASE1_EXIT=1
echo "--- textinput ---"
run_with_retry "textinput" bash "$TEST_SCRIPTS/ios/textinput.sh" || PHASE3_EXIT=1
echo "--- permission ---"
run_with_retry "permission" bash "$TEST_SCRIPTS/ios/permission.sh" || PHASE4_EXIT=1
echo "--- securestorage ---"
run_with_retry "securestorage" bash "$TEST_SCRIPTS/ios/securestorage.sh" || PHASE7_EXIT=1
echo "--- image ---"
run_with_retry "image" bash "$TEST_SCRIPTS/ios/image.sh" || PHASE6_EXIT=1
echo "--- node-pool ---"
run_with_retry "node-pool" bash "$TEST_SCRIPTS/ios/node-pool.sh" || PHASE5_EXIT=1

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

if [ $PHASE4_EXIT -eq 0 ]; then
    PHASE4_OK=1
    echo ""
    echo "PHASE 4 PASSED"
else
    PHASE4_OK=0
    echo ""
    echo "PHASE 4 FAILED"
fi

if [ $PHASE5_EXIT -eq 0 ]; then
    PHASE5_OK=1
    echo ""
    echo "PHASE 5 PASSED"
else
    PHASE5_OK=0
    echo ""
    echo "PHASE 5 FAILED"
fi

if [ $PHASE6_EXIT -eq 0 ]; then
    PHASE6_OK=1
    echo ""
    echo "PHASE 6 PASSED"
else
    PHASE6_OK=0
    echo ""
    echo "PHASE 6 FAILED"
fi

if [ $PHASE7_EXIT -eq 0 ]; then
    PHASE7_OK=1
    echo ""
    echo "PHASE 7 PASSED"
else
    PHASE7_OK=0
    echo ""
    echo "PHASE 7 FAILED"
fi

# ===========================================================================
# Final report
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

if [ $PHASE4_OK -eq 1 ]; then
    echo "PASS  Phase 4 — Permission demo app"
else
    echo "FAIL  Phase 4 — Permission demo app"
    FINAL_EXIT=1
fi

if [ $PHASE5_OK -eq 1 ]; then
    echo "PASS  Phase 5 — Node pool stress test (300 nodes, dynamic pool)"
else
    echo "FAIL  Phase 5 — Node pool stress test (300 nodes, dynamic pool)"
    FINAL_EXIT=1
fi

if [ $PHASE6_OK -eq 1 ]; then
    echo "PASS  Phase 6 — Image demo app"
else
    echo "FAIL  Phase 6 — Image demo app"
    FINAL_EXIT=1
fi

if [ $PHASE7_OK -eq 1 ]; then
    echo "PASS  Phase 7 — SecureStorage demo app"
else
    echo "FAIL  Phase 7 — SecureStorage demo app"
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
