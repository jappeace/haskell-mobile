# watchOS static library — thin wrapper around lib.nix.
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
lib.mkWatchOSLib {
  haskellMobileSrc = ../.;
  inherit mainModule simulator;
  crossDeps = iosDeps;
}
