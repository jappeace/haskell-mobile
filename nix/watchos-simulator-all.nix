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

  secureStorageWatchos = import ./watchos.nix {
    inherit sources;
    mainModule = ../test/SecureStorageDemoMain.hs;
    simulator = true;
  };
  secureStorageSimApp = lib.mkWatchOSSimulatorApp {
    watchosLib = secureStorageWatchos;
    watchosSrc = ../watchos;
    name = "haskell-mobile-watchos-securestorage-simulator-app";
  };

  imageWatchos = import ./watchos.nix {
    inherit sources;
    mainModule = ../test/ImageDemoMain.hs;
    simulator = true;
  };
  imageSimApp = lib.mkWatchOSSimulatorApp {
    watchosLib = imageWatchos;
    watchosSrc = ../watchos;
    name = "haskell-mobile-watchos-image-simulator-app";
  };

  # watchOS uses a Swift dictionary (unbounded) — no DYNAMIC_NODE_POOL needed.
  # This test just confirms 300 nodes render successfully.
  nodepoolWatchos = import ./watchos.nix {
    inherit sources;
    mainModule = ../test/NodePoolTestMain.hs;
    simulator = true;
  };
  nodepoolSimApp = lib.mkWatchOSSimulatorApp {
    watchosLib = nodepoolWatchos;
    watchosSrc = ../watchos;
    name = "haskell-mobile-watchos-nodepool-simulator-app";
  };

  bleWatchos = import ./watchos.nix {
    inherit sources;
    mainModule = ../test/BleDemoMain.hs;
    simulator = true;
  };
  bleSimApp = lib.mkWatchOSSimulatorApp {
    watchosLib = bleWatchos;
    watchosSrc = ../watchos;
    name = "haskell-mobile-watchos-ble-simulator-app";
  };

  dialogWatchos = import ./watchos.nix {
    inherit sources;
    mainModule = ../test/DialogDemoMain.hs;
    simulator = true;
  };
  dialogSimApp = lib.mkWatchOSSimulatorApp {
    watchosLib = dialogWatchos;
    watchosSrc = ../watchos;
    name = "haskell-mobile-watchos-dialog-simulator-app";
  };

  locationWatchos = import ./watchos.nix {
    inherit sources;
    mainModule = ../test/LocationDemoMain.hs;
    simulator = true;
  };
  locationSimApp = lib.mkWatchOSSimulatorApp {
    watchosLib = locationWatchos;
    watchosSrc = ../watchos;
    name = "haskell-mobile-watchos-location-simulator-app";
  };

  webviewWatchos = import ./watchos.nix {
    inherit sources;
    mainModule = ../test/WebViewDemoMain.hs;
    simulator = true;
  };
  webviewSimApp = lib.mkWatchOSSimulatorApp {
    watchosLib = webviewWatchos;
    watchosSrc = ../watchos;
    name = "haskell-mobile-watchos-webview-simulator-app";
  };

  authSessionWatchos = import ./watchos.nix {
    inherit sources;
    mainModule = ../test/AuthSessionDemoMain.hs;
    simulator = true;
  };
  authSessionSimApp = lib.mkWatchOSSimulatorApp {
    watchosLib = authSessionWatchos;
    watchosSrc = ../watchos;
    name = "haskell-mobile-watchos-authsession-simulator-app";
  };

  cameraWatchos = import ./watchos.nix {
    inherit sources;
    mainModule = ../test/CameraDemoMain.hs;
    simulator = true;
  };
  cameraSimApp = lib.mkWatchOSSimulatorApp {
    watchosLib = cameraWatchos;
    watchosSrc = ../watchos;
    name = "haskell-mobile-watchos-camera-simulator-app";
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
SECURE_STORAGE_SHARE_DIR="${secureStorageSimApp}/share/watchos"
IMAGE_SHARE_DIR="${imageSimApp}/share/watchos"
NODEPOOL_SHARE_DIR="${nodepoolSimApp}/share/watchos"
BLE_SHARE_DIR="${bleSimApp}/share/watchos"
DIALOG_SHARE_DIR="${dialogSimApp}/share/watchos"
LOCATION_SHARE_DIR="${locationSimApp}/share/watchos"
WEBVIEW_SHARE_DIR="${webviewSimApp}/share/watchos"
AUTH_SESSION_SHARE_DIR="${authSessionSimApp}/share/watchos"
CAMERA_SHARE_DIR="${cameraSimApp}/share/watchos"
TEST_SCRIPTS="${testScripts}"

# --- Temp working directory ---
WORK_DIR=$(mktemp -d /tmp/haskell-mobile-watchos-sim-all-XXXX)
SIM_UDID=""

# Phase result tracking
PHASE1_OK=0
PHASE2_OK=0
PHASE3_OK=0
PHASE4_OK=0
PHASE5_OK=0
PHASE6_OK=0
PHASE7_OK=0
PHASE8_OK=0
PHASE9_OK=0

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

# --- .a size guard (see docs/ci-ram-regression-110.md) ---
# Fail fast if any test .a exceeds the limit.
A_MAX_MB=120
SIZE_FAIL=0
for share_dir in \
    "$COUNTER_SHARE_DIR" \
    "$SCROLL_SHARE_DIR" \
    "$TEXTINPUT_SHARE_DIR" \
    "$SECURE_STORAGE_SHARE_DIR" \
    "$IMAGE_SHARE_DIR" \
    "$NODEPOOL_SHARE_DIR" \
    "$BLE_SHARE_DIR" \
    "$DIALOG_SHARE_DIR" \
    "$AUTH_SESSION_SHARE_DIR"; do
    a_path="$share_dir/lib/libHaskellMobile.a"
    A_BYTES=$(stat -f %z "$a_path" 2>/dev/null || stat -c %s "$a_path" 2>/dev/null || echo 0)
    A_MB=$((A_BYTES / 1048576))
    A_LABEL=$(echo "$share_dir" | grep -oE '[^/]+/share' | sed 's|/share||')
    if [ "$A_MB" -gt "$A_MAX_MB" ]; then
        echo "FAIL  $A_LABEL .a is ''${A_MB} MB (limit: ''${A_MAX_MB} MB)"
        SIZE_FAIL=1
    else
        echo "OK    $A_LABEL .a is ''${A_MB} MB"
    fi
done
if [ "$SIZE_FAIL" -eq 1 ]; then
    echo ""
    echo "FATAL: .a size limit exceeded. See docs/ci-ram-regression-110.md"
    exit 1
fi
echo ""

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
cp "$COUNTER_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/counter/include/"
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
cp "$SCROLL_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/scroll/include/"
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
cp "$TEXTINPUT_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/textinput/include/"
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

# --- Stage and build node-pool test app ---
echo "=== Staging image test app ==="
mkdir -p "$WORK_DIR/image/lib" "$WORK_DIR/image/include"
cp "$IMAGE_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/image/lib/"
cp "$IMAGE_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/image/include/"
cp -r "$IMAGE_SHARE_DIR/HaskellMobile" "$WORK_DIR/image/"
cp "$IMAGE_SHARE_DIR/project.yml" "$WORK_DIR/image/"
chmod -R u+w "$WORK_DIR/image"

echo "=== Generating image Xcode project ==="
cd "$WORK_DIR/image"
${xcodegen}/bin/xcodegen generate

echo "=== Building image test app for watchOS simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk watchsimulator \
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

# --- Stage and build securestorage demo app ---
echo "=== Staging securestorage demo app ==="
mkdir -p "$WORK_DIR/securestorage/lib" "$WORK_DIR/securestorage/include"
cp "$SECURE_STORAGE_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/securestorage/lib/"
cp "$SECURE_STORAGE_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/securestorage/include/"
cp -r "$SECURE_STORAGE_SHARE_DIR/HaskellMobile" "$WORK_DIR/securestorage/"
cp "$SECURE_STORAGE_SHARE_DIR/project.yml" "$WORK_DIR/securestorage/"
chmod -R u+w "$WORK_DIR/securestorage"

echo "=== Generating securestorage Xcode project ==="
cd "$WORK_DIR/securestorage"
${xcodegen}/bin/xcodegen generate

echo "=== Building securestorage demo app for watchOS simulator (ad-hoc signed for Keychain entitlements) ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk watchsimulator \
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

echo "=== Staging node-pool test app ==="
mkdir -p "$WORK_DIR/nodepool/lib" "$WORK_DIR/nodepool/include"
cp "$NODEPOOL_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/nodepool/lib/"
cp "$NODEPOOL_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/nodepool/include/"
cp -r "$NODEPOOL_SHARE_DIR/HaskellMobile" "$WORK_DIR/nodepool/"
cp "$NODEPOOL_SHARE_DIR/project.yml" "$WORK_DIR/nodepool/"
chmod -R u+w "$WORK_DIR/nodepool"

echo "=== Generating node-pool Xcode project ==="
cd "$WORK_DIR/nodepool"
${xcodegen}/bin/xcodegen generate

echo "=== Building node-pool test app for watchOS simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk watchsimulator \
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

# --- Stage and build BLE demo app ---
echo "=== Staging BLE demo app ==="
mkdir -p "$WORK_DIR/ble/lib" "$WORK_DIR/ble/include"
cp "$BLE_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/ble/lib/"
cp "$BLE_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/ble/include/"
cp -r "$BLE_SHARE_DIR/HaskellMobile" "$WORK_DIR/ble/"
cp "$BLE_SHARE_DIR/project.yml" "$WORK_DIR/ble/"
chmod -R u+w "$WORK_DIR/ble"

echo "=== Generating BLE Xcode project ==="
cd "$WORK_DIR/ble"
${xcodegen}/bin/xcodegen generate

echo "=== Building BLE demo app for watchOS simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk watchsimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/ble-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

BLE_APP=$(find "$WORK_DIR/ble-build" -name "*.app" -type d | head -1)
if [ -z "$BLE_APP" ]; then
    echo "ERROR: Could not find BLE .app bundle"
    exit 1
fi
echo "BLE app: $BLE_APP"

# --- Stage and build dialog demo app ---
echo "=== Staging dialog demo app ==="
mkdir -p "$WORK_DIR/dialog/lib" "$WORK_DIR/dialog/include"
cp "$DIALOG_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/dialog/lib/"
cp "$DIALOG_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/dialog/include/"
cp -r "$DIALOG_SHARE_DIR/HaskellMobile" "$WORK_DIR/dialog/"
cp "$DIALOG_SHARE_DIR/project.yml" "$WORK_DIR/dialog/"
chmod -R u+w "$WORK_DIR/dialog"

echo "=== Generating dialog Xcode project ==="
cd "$WORK_DIR/dialog"
${xcodegen}/bin/xcodegen generate

echo "=== Building dialog demo app for watchOS simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk watchsimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/dialog-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

DIALOG_APP=$(find "$WORK_DIR/dialog-build" -name "*.app" -type d | head -1)
if [ -z "$DIALOG_APP" ]; then
    echo "ERROR: Could not find dialog .app bundle"
    exit 1
fi
echo "Dialog app: $DIALOG_APP"

# --- Stage and build location demo app ---
echo "=== Staging location demo app ==="
mkdir -p "$WORK_DIR/location/lib" "$WORK_DIR/location/include"
cp "$LOCATION_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/location/lib/"
cp "$LOCATION_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/location/include/"
cp -r "$LOCATION_SHARE_DIR/HaskellMobile" "$WORK_DIR/location/"
cp "$LOCATION_SHARE_DIR/project.yml" "$WORK_DIR/location/"
chmod -R u+w "$WORK_DIR/location"

echo "=== Generating location Xcode project ==="
cd "$WORK_DIR/location"
${xcodegen}/bin/xcodegen generate

echo "=== Building location demo app for watchOS simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk watchsimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/location-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

LOCATION_APP=$(find "$WORK_DIR/location-build" -name "*.app" -type d | head -1)
if [ -z "$LOCATION_APP" ]; then
    echo "ERROR: Could not find location .app bundle"
    exit 1
fi
echo "Location app: $LOCATION_APP"

# --- Stage and build webview demo app ---
echo "=== Staging webview demo app ==="
mkdir -p "$WORK_DIR/webview/lib" "$WORK_DIR/webview/include"
cp "$WEBVIEW_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/webview/lib/"
cp "$WEBVIEW_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/webview/include/"
cp -r "$WEBVIEW_SHARE_DIR/HaskellMobile" "$WORK_DIR/webview/"
cp "$WEBVIEW_SHARE_DIR/project.yml" "$WORK_DIR/webview/"
chmod -R u+w "$WORK_DIR/webview"

# --- Stage and build camera demo app ---
echo "=== Staging camera demo app ==="
mkdir -p "$WORK_DIR/camera/lib" "$WORK_DIR/camera/include"
cp "$CAMERA_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/camera/lib/"
cp "$CAMERA_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/camera/include/"
cp -r "$CAMERA_SHARE_DIR/HaskellMobile" "$WORK_DIR/camera/"
cp "$CAMERA_SHARE_DIR/project.yml" "$WORK_DIR/camera/"
chmod -R u+w "$WORK_DIR/camera"

echo "=== Generating webview Xcode project ==="
cd "$WORK_DIR/webview"
${xcodegen}/bin/xcodegen generate

echo "=== Building webview demo app for simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk watchsimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/webview-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

WEBVIEW_APP=$(find "$WORK_DIR/webview-build" -name "*.app" -type d | head -1)
if [ -z "$WEBVIEW_APP" ]; then
    echo "ERROR: Could not find webview .app bundle"
    exit 1
fi
echo "WebView app: $WEBVIEW_APP"

# --- Stage and build authsession demo app ---
echo "=== Staging authsession demo app ==="
mkdir -p "$WORK_DIR/authsession/lib" "$WORK_DIR/authsession/include"
cp "$AUTH_SESSION_SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/authsession/lib/"
cp "$AUTH_SESSION_SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/authsession/include/"
cp -r "$AUTH_SESSION_SHARE_DIR/HaskellMobile" "$WORK_DIR/authsession/"
cp "$AUTH_SESSION_SHARE_DIR/project.yml" "$WORK_DIR/authsession/"
chmod -R u+w "$WORK_DIR/authsession"

echo "=== Generating authsession Xcode project ==="
cd "$WORK_DIR/authsession"
${xcodegen}/bin/xcodegen generate

echo "=== Building authsession demo app for simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk watchsimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/authsession-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

AUTH_SESSION_APP=$(find "$WORK_DIR/authsession-build" -name "*.app" -type d | head -1)
if [ -z "$AUTH_SESSION_APP" ]; then
    echo "ERROR: Could not find authsession .app bundle"
    exit 1
fi
echo "AuthSession app: $AUTH_SESSION_APP"

echo "=== Generating camera Xcode project ==="
cd "$WORK_DIR/camera"
${xcodegen}/bin/xcodegen generate

echo "=== Building camera demo app for watchOS simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk watchsimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/camera-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

CAMERA_APP=$(find "$WORK_DIR/camera-build" -name "*.app" -type d | head -1)
if [ -z "$CAMERA_APP" ]; then
    echo "ERROR: Could not find camera .app bundle"
    exit 1
fi
echo "Camera app: $CAMERA_APP"

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
export SIM_UDID BUNDLE_ID LOG_SUBSYSTEM COUNTER_APP SCROLL_APP TEXTINPUT_APP SECURE_STORAGE_APP IMAGE_APP NODEPOOL_APP BLE_APP DIALOG_APP LOCATION_APP WEBVIEW_APP AUTH_SESSION_APP CAMERA_APP WORK_DIR

PHASE1_EXIT=0
PHASE2_EXIT=0
PHASE3_EXIT=0
PHASE4_EXIT=0
PHASE5_EXIT=0
PHASE6_EXIT=0
PHASE7_EXIT=0
PHASE8_EXIT=0
PHASE9_EXIT=0

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
echo "--- securestorage ---"
run_with_retry "securestorage" bash "$TEST_SCRIPTS/watchos/securestorage.sh" || PHASE6_EXIT=1
echo "--- image ---"
run_with_retry "image" bash "$TEST_SCRIPTS/watchos/image.sh" || PHASE5_EXIT=1
echo "--- node-pool ---"
run_with_retry "node-pool" bash "$TEST_SCRIPTS/watchos/node-pool.sh" || PHASE4_EXIT=1
echo "--- ble ---"
run_with_retry "ble" bash "$TEST_SCRIPTS/watchos/ble.sh" || PHASE6_EXIT=1
echo "--- dialog ---"
run_with_retry "dialog" bash "$TEST_SCRIPTS/watchos/dialog.sh" || PHASE7_EXIT=1
echo "--- location ---"
run_with_retry "location" bash "$TEST_SCRIPTS/watchos/location.sh" || PHASE6_EXIT=1
echo "--- webview ---"
run_with_retry "webview" bash "$TEST_SCRIPTS/watchos/webview.sh" || PHASE8_EXIT=1
echo "--- authsession ---"
run_with_retry "authsession" bash "$TEST_SCRIPTS/watchos/authsession.sh" || PHASE9_EXIT=1
echo "--- camera ---"
run_with_retry "camera" bash "$TEST_SCRIPTS/watchos/camera.sh" || PHASE9_EXIT=1

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

if [ $PHASE8_EXIT -eq 0 ]; then
    PHASE8_OK=1
    echo ""
    echo "PHASE 8 PASSED"
else
    PHASE8_OK=0
    echo ""
    echo "PHASE 8 FAILED"
fi

if [ $PHASE9_EXIT -eq 0 ]; then
    PHASE9_OK=1
    echo ""
    echo "PHASE 9 PASSED"
else
    PHASE9_OK=0
    echo ""
    echo "PHASE 9 FAILED"
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
    echo "PASS  Phase 4 — Node pool stress test (300 nodes)"
else
    echo "FAIL  Phase 4 — Node pool stress test (300 nodes)"
    FINAL_EXIT=1
fi

if [ $PHASE5_OK -eq 1 ]; then
    echo "PASS  Phase 5 — Image demo app"
else
    echo "FAIL  Phase 5 — Image demo app"
    FINAL_EXIT=1
fi

if [ $PHASE6_OK -eq 1 ]; then
    echo "PASS  Phase 6 — SecureStorage + BLE + Location demo app"
else
    echo "FAIL  Phase 6 — SecureStorage + BLE + Location demo app"
    FINAL_EXIT=1
fi

if [ $PHASE7_OK -eq 1 ]; then
    echo "PASS  Phase 7 — Dialog demo app"
else
    echo "FAIL  Phase 7 — Dialog demo app"
    FINAL_EXIT=1
fi

if [ $PHASE8_OK -eq 1 ]; then
    echo "PASS  Phase 8 — WebView demo app"
else
    echo "FAIL  Phase 8 — WebView demo app"
    FINAL_EXIT=1
fi

if [ $PHASE9_OK -eq 1 ]; then
    echo "PASS  Phase 9 — AuthSession demo app"
else
    echo "FAIL  Phase 9 — AuthSession demo app"
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
