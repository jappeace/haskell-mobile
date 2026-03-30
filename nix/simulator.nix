# iOS Simulator lifecycle test — thin wrapper around lib.nix.
{ sources ? import ../npins }:
let
  lib = import ./lib.nix { inherit sources; };
  simulatorApp = import ./simulator-app.nix { inherit sources; };
in
lib.mkSimulatorTest {
  inherit simulatorApp;
  bundleId = "me.jappie.haskellmobile";
  scheme = "HaskellMobile";
  name = "haskell-mobile-simulator-test";
}
