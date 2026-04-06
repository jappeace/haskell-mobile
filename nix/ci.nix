{ sources ? import ../npins }:
let
  isDarwin = builtins.currentSystem == "aarch64-darwin"
          || builtins.currentSystem == "x86_64-darwin";
in {
  # Build artifacts
  native = import ../default.nix {};
  android = import ./android.nix { inherit sources; };
  apk = import ./apk.nix { inherit sources; };
  consumer-link-test = import ./test-link-consumer.nix { inherit sources; };

  # Android combined test script (boot + run via CI: nix-build ... -o out && ./out/bin/test-all)
  emulator-all = import ./emulator-all.nix { inherit sources; };
} // (if isDarwin then {
  # iOS library for artifact upload
  ios-lib = import ./ios.nix { inherit sources; };
  # iOS combined test script (boot + run via CI: nix-build ... -o out && ./out/bin/test-all-ios)
  simulator-all = import ./simulator-all.nix { inherit sources; };
} else {})
