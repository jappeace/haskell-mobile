# Android emulator lifecycle test — thin wrapper around lib.nix.
{ sources ? import ../npins }:
let
  lib = import ./lib.nix { inherit sources; };
  apk = import ./apk.nix { inherit sources; };
in
lib.mkEmulatorTest {
  inherit apk;
  apkFileName = "haskell-mobile.apk";
  packageName = "me.jappie.haskellmobile";
  name = "haskell-mobile-emulator-test";
}
