# iOS static library — thin wrapper around lib.nix.
{ sources ? import ../npins
, simulator ? false
, mainModule ? ../app/MobileMain.hs
}:
let
  lib = import ./lib.nix { inherit sources; };
  iosDeps = import ./ios-deps.nix { inherit sources; };
in
lib.mkIOSLib {
  haskellMobileSrc = ../.;
  inherit mainModule simulator;
  crossDeps = iosDeps;
}
