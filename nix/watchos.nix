# watchOS static library — thin wrapper around lib.nix.
{ sources ? import ../npins
, simulator ? false
, mainModule ? ../app/MobileMain.hs
, consumerCabalFile ? null
, consumerCabal2Nix ? null
}:
let
  lib = import ./lib.nix { inherit sources; };
  iosDeps = import ./ios-deps.nix {
    inherit sources consumerCabalFile consumerCabal2Nix;
  };
in
lib.mkWatchOSLib {
  haskellMobileSrc = ../.;
  inherit mainModule simulator;
  crossDeps = iosDeps;
}
