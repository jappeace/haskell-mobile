# Collect pre-built Haskell package outputs into a single directory.
#
# Takes a list of nixpkgs haskellPackages derivations (already resolved
# transitively by resolve-deps.nix) and collects their .conf / .a files:
#   $out/lib/*.a       — static archives (only those referenced by hs-libraries)
#   $out/pkgdb/        — GHC package database (.conf + cache)
#
# This uses standard nixpkgs outputs rather than manual cabal builds.
{ pkgs
, ghcPkgCmd         # full path to ghc-pkg (or cross ghc-pkg)
, deps              # list of haskellPackages derivations (from resolve-deps.nix)
}:
let
  depsList = builtins.concatStringsSep " " (map toString deps);

in pkgs.runCommand "haskell-mobile-collected-deps" {
  nativeBuildInputs = [ pkgs.findutils ];
} ''
  mkdir -p $out/lib $out/pkgdb

  for pkg in ${depsList}; do
    echo "Processing: $pkg"

    # Copy .conf files, skipping benchmark/test sub-libraries
    for conf in $(find "$pkg" -name "*.conf" -path "*/package.conf.d/*"); do
      LIB_NAME=$(grep '^lib-name:' "$conf" | sed 's/^lib-name: *//' || true)
      case "$LIB_NAME" in
        *benchmark*|*test*) echo "  skip sub-lib: $LIB_NAME"; continue ;;
      esac
      cp "$conf" $out/pkgdb/

      # Copy only .a files referenced by this .conf's hs-libraries field
      HS_LIBS=$(grep '^hs-libraries:' "$conf" | sed 's/^hs-libraries: *//')
      for lib in $HS_LIBS; do
        aFile=$(find "$pkg" -name "lib$lib.a" ! -name "*_p.a" | head -1)
        if [ -n "$aFile" ]; then
          cp "$aFile" $out/lib/
        fi
      done
    done
  done

  ${ghcPkgCmd} --package-db=$out/pkgdb recache

  echo "=== Package database ==="
  ${ghcPkgCmd} --package-db=$out/pkgdb list

  echo "=== Libraries ==="
  ls -lh $out/lib/
''
