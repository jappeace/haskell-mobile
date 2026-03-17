# Shared haskell.nix project definition.
# Takes pkgs (with haskell-nix overlay applied) and returns the project.
# Used by both android.nix and ios.nix.
{ pkgs }:
pkgs.haskell-nix.project {
  compiler-nix-name = "ghc963";
  src = pkgs.haskell-nix.haskellLib.cleanGit {
    name = "haskell-mobile";
    src = ../.;
  };
}
