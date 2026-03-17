# Build the mac2ios tool from zw3rk/mobile-core-tools.
# Patches Mach-O platform tags from macOS to iOS in static archives.
{ sources ? import ../npins
, pkgs ? import sources.nixpkgs {}
}:
pkgs.stdenv.mkDerivation {
  pname = "mac2ios";
  version = "unstable";
  src = sources.mobile-core-tools;
  buildPhase = ''
    $CC -o mac2ios mac2ios.c
  '';
  installPhase = ''
    mkdir -p $out/bin
    cp mac2ios $out/bin/
  '';
}
