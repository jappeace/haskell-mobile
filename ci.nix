let
  isDarwin = builtins.currentSystem == "aarch64-darwin"
          || builtins.currentSystem == "x86_64-darwin";
in {
  native = import ./default.nix {};
  android = import ./nix/android.nix {};
  apk = import ./nix/apk.nix {};
} // (if isDarwin then {
  ios = import ./nix/ios.nix {};
} else {})
