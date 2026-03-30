# iOS static library — thin wrapper around lib.nix.
{ sources ? import ../npins
, simulator ? false
, mainModule ? ../app/MobileMain.hs
}:
let
  lib = import ./lib.nix { inherit sources; };
in
lib.mkIOSLib {
  haskellMobileSrc = ../.;
  inherit mainModule simulator;
}
