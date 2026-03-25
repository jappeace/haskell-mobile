{ sources ? import ../npins }:
let
  pkgs = import sources.nixpkgs {
    config.allowUnfree = true;
    config.android_sdk.accept_license = true;
  };
  isDarwin = builtins.currentSystem == "aarch64-darwin"
          || builtins.currentSystem == "x86_64-darwin";

  runTest = name: testDrv: scriptName:
    pkgs.runCommand "run-${name}" { __noChroot = true; } ''
      ${testDrv}/bin/${scriptName}
      touch $out
    '';
in {
  # Build artifacts
  native = import ../default.nix {};
  android = import ./android.nix { inherit sources; };
  apk = import ./apk.nix { inherit sources; };

  # Android tests (Linux)
  emulator-test = runTest "emulator-test"
    (import ./emulator.nix { inherit sources; }) "test-lifecycle";
  emulator-ui-test = runTest "emulator-ui-test"
    (import ./emulator-ui.nix { inherit sources; }) "test-ui";
  emulator-ui-buttons-test = runTest "emulator-ui-buttons-test"
    (import ./emulator-ui-buttons.nix { inherit sources; }) "test-ui-buttons";
} // (if isDarwin then {
  ios = import ./ios.nix { inherit sources; };
  simulator-test = runTest "simulator-test"
    (import ./simulator.nix { inherit sources; }) "test-lifecycle-ios";
  simulator-ui-test = runTest "simulator-ui-test"
    (import ./simulator-ui.nix { inherit sources; }) "test-ui-ios";
  simulator-ui-buttons-test = runTest "simulator-ui-buttons-test"
    (import ./simulator-ui-buttons.nix { inherit sources; }) "test-ui-buttons-ios";
} else {})
