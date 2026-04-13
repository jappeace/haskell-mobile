# iOS static library — thin wrapper around lib.nix.
#
# maxNodes / dynamicNodePool are not used here — UIBridgeIOS.m is compiled
# by Xcode, not GHC.  These flags flow through mkSimulatorApp instead
# (which injects OTHER_CFLAGS into project.yml).
{ sources ? import ../npins
, simulator ? false
, mainModule ? ../test/ScrollDemoMain.hs
, consumerCabalFile ? null
, consumerCabal2Nix ? null
, hpkgs ? (_: _: {})       # consumer haskellPackages overrides
}:
let
  lib = import ./lib.nix { inherit sources; };
  iosDeps = import ./ios-deps.nix {
    inherit sources consumerCabalFile consumerCabal2Nix hpkgs;
  };
in
lib.mkIOSLib {
  hatterSrc = ../.;
  inherit mainModule simulator;
  crossDeps = iosDeps;
}
