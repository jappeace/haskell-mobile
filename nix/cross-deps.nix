# Cross-compile Hackage packages for aarch64-android.
#
# Uses cabal-install with the cross-GHC to build packages offline from
# locally-fetched sources.  The output contains:
#   $out/lib/*.a       — static archives
#   $out/hi/           — interface files (.hi)
#   $out/pkgdb/        — GHC package database (.conf + cache)
#
# Currently builds: direct-sqlite (bundled sqlite3.c, no systemlib).
{ sources }:
let
  pkgs = import sources.nixpkgs {
    config.allowUnfree = true;
    config.android_sdk.accept_license = true;
  };

  # Cross-compilation toolchain (same as lib.nix)
  androidPkgs = pkgs.pkgsCross.aarch64-android-prebuilt;
  ghc = androidPkgs.haskellPackages.ghc;
  ghcBin = "${ghc}/bin";
  ghcPrefix = ghc.targetPrefix;           # "aarch64-unknown-linux-android-"
  ghcCmd = "${ghcBin}/${ghcPrefix}ghc";
  ghcPkgCmd = "${ghcBin}/${ghcPrefix}ghc-pkg";
  hsc2hsCmd = "${ghcBin}/${ghcPrefix}hsc2hs";

  # Fetch direct-sqlite source tarball
  directSqliteSrc = pkgs.fetchurl {
    url = "https://hackage.haskell.org/package/direct-sqlite-2.3.29/direct-sqlite-2.3.29.tar.gz";
    sha256 = "1byhnk4jcv83iw7rqw48p8xk6s2dfs1dh6ibwwzkc9m9lwwcwajz";
  };

in pkgs.stdenv.mkDerivation {
  name = "haskell-mobile-cross-deps";

  dontUnpack = true;

  nativeBuildInputs = [ ghc pkgs.cabal-install ];
  buildInputs = [ androidPkgs.libffi androidPkgs.gmp ];

  buildPhase = ''
    export HOME=$TMPDIR/home
    mkdir -p $HOME

    # --- Pre-create cabal config to prevent network access ---
    # Without this, cabal tries to fetch the Hackage mirror list on first
    # run, which fails inside the nix sandbox (no network).
    mkdir -p $HOME/.config/cabal
    cat > $HOME/.config/cabal/config << 'CABALCFG'
-- Minimal config for offline cross-compilation (no network)
repository hackage.haskell.org
  url: http://hackage.haskell.org/
  secure: False

nix: False
CABALCFG

    # Create an empty package index so cabal doesn't try to download one.
    # The 01-index.tar must exist even for --offline to work.
    mkdir -p $HOME/.local/state/cabal/repo/hackage.haskell.org
    tar cf $HOME/.local/state/cabal/repo/hackage.haskell.org/01-index.tar --files-from /dev/null
    cp $HOME/.local/state/cabal/repo/hackage.haskell.org/01-index.tar \
       $HOME/.local/state/cabal/repo/hackage.haskell.org/01-index.tar.idx 2>/dev/null || true

    # --- Unpack direct-sqlite ---
    mkdir -p $TMPDIR/deps
    cd $TMPDIR/deps
    tar xzf ${directSqliteSrc}

    # --- Patch out build-tool-depends: hsc2hs ---
    # Cabal tries to cross-compile hsc2hs, producing an ARM binary that
    # can't run on the build host.  The cross-GHC's hsc2hs is already
    # available via --with-hsc2hs.
    sed -i 's/^  build-tool-depends:.*hsc2hs.*/  -- &/' \
      direct-sqlite-2.3.29/direct-sqlite.cabal

    # Verify the patch took effect
    if grep -q '^  build-tool-depends:.*hsc2hs' direct-sqlite-2.3.29/direct-sqlite.cabal; then
      echo "ERROR: Failed to patch out hsc2hs build-tool-depends"
      exit 1
    fi

    # --- Create a wrapper cabal project ---
    # We need a top-level project so cabal resolves direct-sqlite as a
    # local package.  The "wrapper" library exists only to pull in the
    # dependency; we only care about direct-sqlite's build artifacts.
    mkdir -p $TMPDIR/project/src
    cd $TMPDIR/project

    cat > cross-deps.cabal << 'EOF'
cabal-version: 3.0
name:          cross-deps
version:       0.1
build-type:    Simple

library
  default-language: Haskell2010
  build-depends: base, direct-sqlite
  exposed-modules: CrossDeps
  hs-source-dirs: src
EOF

    echo "module CrossDeps where" > src/CrossDeps.hs

    cat > cabal.project << EOF
packages: .
          $TMPDIR/deps/direct-sqlite-2.3.29/

package direct-sqlite
  flags: -systemlib

tests: False
benchmarks: False
EOF

    # --- Create symlinks so cabal finds cross tools by short name ---
    # cabal searches PATH for "ghc-pkg" and "hsc2hs" when the compiler
    # path is overridden.
    mkdir -p $TMPDIR/cross-bin
    ln -s ${ghcCmd} $TMPDIR/cross-bin/ghc
    ln -s ${ghcPkgCmd} $TMPDIR/cross-bin/ghc-pkg
    ln -s ${hsc2hsCmd} $TMPDIR/cross-bin/hsc2hs

    # --- Build direct-sqlite with cross-GHC ---
    PATH="$TMPDIR/cross-bin:${ghcBin}:$PATH" \
    cabal build --offline \
      --with-compiler=${ghcCmd} \
      --with-hc-pkg=${ghcPkgCmd} \
      --with-hsc2hs=${hsc2hsCmd} \
      --extra-lib-dirs=${androidPkgs.gmp}/lib \
      --extra-lib-dirs=${androidPkgs.libffi}/lib \
      lib:direct-sqlite
  '';

  installPhase = ''
    # --- Locate build artifacts ---
    BUILD_DIR=$(echo $TMPDIR/project/dist-newstyle/build/aarch64-android/ghc-*/direct-sqlite-*/build)
    if [ ! -d "$BUILD_DIR" ]; then
      echo "ERROR: Could not find direct-sqlite build directory"
      echo "dist-newstyle contents:"
      find $TMPDIR/project/dist-newstyle -type d 2>/dev/null | head -20
      exit 1
    fi
    echo "Build directory: $BUILD_DIR"

    # --- Copy static archive ---
    mkdir -p $out/lib
    cp "$BUILD_DIR"/libHSdirect-sqlite-*.a $out/lib/
    echo "Copied .a:"
    ls -lh $out/lib/

    # --- Copy interface files (preserving directory structure) ---
    mkdir -p $out/hi
    (cd "$BUILD_DIR" && find Database -name '*.hi' -exec cp --parents {} $out/hi/ \;)
    echo "Copied .hi files:"
    find $out/hi -name '*.hi'

    # --- Create package database ---
    # Generate a minimal package conf and register it with ghc-pkg.
    mkdir -p $out/pkgdb

    # Find the unit ID from the .a file name
    A_FILE=$(basename $out/lib/libHS*.a)
    # libHSdirect-sqlite-2.3.29-inplace.a → direct-sqlite-2.3.29-inplace
    UNIT_ID=''${A_FILE#libHS}
    UNIT_ID=''${UNIT_ID%.a}

    # Resolve actual unit IDs of boot library dependencies from the cross-GHC
    BASE_ID=$(${ghcPkgCmd} field base id --simple-output 2>/dev/null || echo "base-4.20.0.0")
    BYTESTRING_ID=$(${ghcPkgCmd} field bytestring id --simple-output 2>/dev/null || echo "bytestring-0.12.1.0")
    TEXT_ID=$(${ghcPkgCmd} field text id --simple-output 2>/dev/null || echo "text-2.1.1")

    cat > $out/pkgdb/direct-sqlite.conf << CONF
name: direct-sqlite
version: 2.3.29
id: $UNIT_ID
key: $UNIT_ID
exposed: True
exposed-modules: Database.SQLite3 Database.SQLite3.Bindings Database.SQLite3.Bindings.Types Database.SQLite3.Direct
import-dirs: $out/hi
library-dirs: $out/lib
hs-libraries: HSdirect-sqlite-2.3.29-inplace
depends:
    $BASE_ID
    $BYTESTRING_ID
    $TEXT_ID
CONF

    ${ghcPkgCmd} --package-db=$out/pkgdb recache

    echo "Package database:"
    ${ghcPkgCmd} --package-db=$out/pkgdb list
  '';
}
