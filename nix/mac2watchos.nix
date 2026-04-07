# Build the mac2watchos tool.
# Patches Mach-O platform tags from macOS to watchOS in static archives.
{ sources ? import ../npins
, pkgs ? import sources.nixpkgs {}
}:
pkgs.stdenv.mkDerivation {
  pname = "mac2watchos";
  version = "unstable";
  src = ../cbits;
  buildPhase = ''
    $CC -o mac2watchos mac2watchos.c
  '';
  installPhase = ''
    mkdir -p $out/bin
    cp mac2watchos $out/bin/
  '';
}
