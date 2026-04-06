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
  consumer-link-test = import ./test-link-consumer.nix { inherit sources; };

  # Android tests (Linux) — single emulator session covering all suites
  emulator-all-test = runTest "emulator-all-test"
    (import ./emulator-all.nix { inherit sources; }) "test-all";
} // (if isDarwin then {
  # ios-lib: kept for artifact upload
  ios-lib = import ./ios.nix { inherit sources; };
  # ios: single simulator session covering all suites
  ios = runTest "simulator-all-test"
    (import ./simulator-all.nix { inherit sources; }) "test-all-ios";
} else {})
