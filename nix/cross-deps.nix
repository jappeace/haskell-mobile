# Cross-compile Hackage packages for aarch64-android.
#
# Uses cabal-install with the cross-GHC to build packages offline from
# locally-fetched sources.  The output contains:
#   $out/lib/*.a       — static archives
#   $out/hi/           — interface files (.hi)
#   $out/pkgdb/        — GHC package database (.conf + cache)
#
# Currently builds: direct-sqlite (bundled sqlite3.c, no systemlib),
# prettyprinter, and toml-parser (for i18n support).
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

  # Wrapper cabal project — just declares `build-depends: direct-sqlite`
  # so cabal resolves it as a local package.  Shared with ios-deps.nix.
  wrapperProject = ./deps-wrapper;
  cabalConfig = ./cabal-config;

  # Fetch source tarballs
  directSqliteSrc = pkgs.fetchurl {
    url = "https://hackage.haskell.org/package/direct-sqlite-2.3.29/direct-sqlite-2.3.29.tar.gz";
    sha256 = "1byhnk4jcv83iw7rqw48p8xk6s2dfs1dh6ibwwzkc9m9lwwcwajz";
  };

  prettyprinterSrc = pkgs.fetchurl {
    url = "https://hackage.haskell.org/package/prettyprinter-1.7.1/prettyprinter-1.7.1.tar.gz";
    sha256 = "sha256-Xm6mkDEU+hGPzDWWM9+37N3suSwGyFPQKne3KyUfC0U=";
  };

  tomlParserSrc = pkgs.fetchurl {
    url = "https://hackage.haskell.org/package/toml-parser-2.0.2.0/toml-parser-2.0.2.0.tar.gz";
    sha256 = "sha256-note5e6pvqJEFzI0eDmo4y6YeJBVpiH1WnLC33qN4ag=";
  };

in pkgs.stdenv.mkDerivation {
  name = "haskell-mobile-cross-deps";

  dontUnpack = true;

  nativeBuildInputs = [ ghc pkgs.cabal-install pkgs.haskellPackages.alex pkgs.haskellPackages.happy ];
  buildInputs = [ androidPkgs.libffi androidPkgs.gmp ];

  buildPhase = ''
    export HOME=$TMPDIR/home
    mkdir -p $HOME

    # --- Pre-create cabal config to prevent network access ---
    # Without this, cabal tries to fetch the Hackage mirror list on first
    # run, which fails inside the nix sandbox (no network).
    mkdir -p $HOME/.config/cabal
    cp ${cabalConfig} $HOME/.config/cabal/config

    # Create an empty package index so cabal doesn't try to download one.
    # The 01-index.tar must exist even for --offline to work.
    mkdir -p $HOME/.local/state/cabal/repo/hackage.haskell.org
    tar cf $HOME/.local/state/cabal/repo/hackage.haskell.org/01-index.tar --files-from /dev/null
    cp $HOME/.local/state/cabal/repo/hackage.haskell.org/01-index.tar \
       $HOME/.local/state/cabal/repo/hackage.haskell.org/01-index.tar.idx 2>/dev/null || true

    # --- Unpack source packages ---
    mkdir -p $TMPDIR/deps
    cd $TMPDIR/deps
    tar xzf ${directSqliteSrc}
    tar xzf ${prettyprinterSrc}
    tar xzf ${tomlParserSrc}

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

    # --- Patch out build-tool-depends for toml-parser ---
    # alex and happy must run on the build host, not the target.
    # The Hackage tarball ships pre-generated .hs files, so we just
    # comment out the build-tool-depends lines.
    # The library's build-tool-depends spans multiple lines:
    #   build-tool-depends:
    #       alex:alex  >= 3.2,
    #       happy:happy >= 1.19,
    # Comment out the alex and happy lines directly.
    sed -i 's/^        alex:alex.*/        -- &/' \
      toml-parser-2.0.2.0/toml-parser.cabal
    sed -i 's/^        happy:happy.*/        -- &/' \
      toml-parser-2.0.2.0/toml-parser.cabal

    # --- Create a wrapper cabal project ---
    # We need a top-level project so cabal resolves direct-sqlite as a
    # local package.  The "wrapper" library exists only to pull in the
    # dependency; we only care about direct-sqlite's build artifacts.
    cp -r ${wrapperProject} $TMPDIR/project
    chmod -R u+w $TMPDIR/project
    cd $TMPDIR/project

    cat > cabal.project << EOF
packages: .
          $TMPDIR/deps/direct-sqlite-2.3.29/
          $TMPDIR/deps/prettyprinter-1.7.1/
          $TMPDIR/deps/toml-parser-2.0.2.0/

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

    # --- Build all deps with cross-GHC ---
    PATH="$TMPDIR/cross-bin:${ghcBin}:$PATH" \
    cabal build --offline \
      --with-compiler=${ghcCmd} \
      --with-hc-pkg=${ghcPkgCmd} \
      --with-hsc2hs=${hsc2hsCmd} \
      --extra-lib-dirs=${androidPkgs.gmp}/lib \
      --extra-lib-dirs=${androidPkgs.libffi}/lib \
      lib:direct-sqlite lib:prettyprinter lib:toml-parser
  '';

  installPhase = ''
    DIST=$TMPDIR/project/dist-newstyle/build/aarch64-android/ghc-*
    mkdir -p $out/lib $out/hi $out/pkgdb

    # --- Helper: install one package's artifacts ---
    install_pkg() {
      local PKG_NAME=$1
      local BUILD_DIR
      BUILD_DIR=$(echo $DIST/$PKG_NAME-*/build)
      if [ ! -d "$BUILD_DIR" ]; then
        echo "ERROR: Could not find $PKG_NAME build directory"
        find $DIST -type d 2>/dev/null | head -30
        exit 1
      fi
      echo "Installing $PKG_NAME from: $BUILD_DIR"

      # Copy static archives
      cp "$BUILD_DIR"/libHS''${PKG_NAME}-*.a $out/lib/ 2>/dev/null || true

      # Copy interface files (preserving directory structure)
      (cd "$BUILD_DIR" && find . -name '*.hi' -exec cp --parents {} $out/hi/ \;) 2>/dev/null || true
    }

    install_pkg direct-sqlite
    install_pkg prettyprinter
    install_pkg toml-parser

    echo "Copied .a files:"
    ls -lh $out/lib/

    echo "Copied .hi files:"
    find $out/hi -name '*.hi'

    # --- Create package database ---
    # Resolve boot library unit IDs from the cross-GHC
    BASE_ID=$(${ghcPkgCmd} field base id --simple-output 2>/dev/null || echo "base-4.20.0.0")
    BYTESTRING_ID=$(${ghcPkgCmd} field bytestring id --simple-output 2>/dev/null || echo "bytestring-0.12.1.0")
    TEXT_ID=$(${ghcPkgCmd} field text id --simple-output 2>/dev/null || echo "text-2.1.1")
    CONTAINERS_ID=$(${ghcPkgCmd} field containers id --simple-output 2>/dev/null || echo "containers-0.7")
    ARRAY_ID=$(${ghcPkgCmd} field array id --simple-output 2>/dev/null || echo "array-0.5.7.0")
    TIME_ID=$(${ghcPkgCmd} field time id --simple-output 2>/dev/null || echo "time-1.12.2")
    TRANSFORMERS_ID=$(${ghcPkgCmd} field transformers id --simple-output 2>/dev/null || echo "transformers-0.6.1.1")
    DEEPSEQ_ID=$(${ghcPkgCmd} field deepseq id --simple-output 2>/dev/null || echo "deepseq-1.5.0.0")

    # --- Helper: extract unit ID from .a filename ---
    get_unit_id() {
      local PKG=$1
      local A_FILE
      A_FILE=$(basename $out/lib/libHS''${PKG}-*.a 2>/dev/null | head -1)
      local UNIT_ID=''${A_FILE#libHS}
      UNIT_ID=''${UNIT_ID%.a}
      echo "$UNIT_ID"
    }

    DS_UNIT_ID=$(get_unit_id direct-sqlite)
    PP_UNIT_ID=$(get_unit_id prettyprinter)
    TP_UNIT_ID=$(get_unit_id toml-parser)

    cat > $out/pkgdb/direct-sqlite.conf << CONF
name: direct-sqlite
version: 2.3.29
id: $DS_UNIT_ID
key: $DS_UNIT_ID
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

    cat > $out/pkgdb/prettyprinter.conf << CONF
name: prettyprinter
version: 1.7.1
id: $PP_UNIT_ID
key: $PP_UNIT_ID
exposed: True
exposed-modules: Prettyprinter Prettyprinter.Internal Prettyprinter.Internal.Type Prettyprinter.Render.String Prettyprinter.Render.Text Prettyprinter.Render.Util.Panic Prettyprinter.Render.Util.SimpleDocTree Prettyprinter.Render.Util.StackMachine Prettyprinter.Symbols.Ascii Prettyprinter.Symbols.Unicode
import-dirs: $out/hi
library-dirs: $out/lib
hs-libraries: HSprettyprinter-1.7.1-inplace
depends:
    $BASE_ID
    $TEXT_ID
    $DEEPSEQ_ID
CONF

    cat > $out/pkgdb/toml-parser.conf << CONF
name: toml-parser
version: 2.0.2.0
id: $TP_UNIT_ID
key: $TP_UNIT_ID
exposed: True
exposed-modules: Toml Toml.Pretty Toml.Schema Toml.Schema.FromValue Toml.Schema.Generic Toml.Schema.Generic.FromValue Toml.Schema.Generic.ToValue Toml.Schema.Matcher Toml.Schema.ParseTable Toml.Schema.ToValue Toml.Semantics Toml.Semantics.Ordered Toml.Semantics.Types Toml.Syntax Toml.Syntax.Lexer Toml.Syntax.Parser Toml.Syntax.Position Toml.Syntax.Token Toml.Syntax.Types
import-dirs: $out/hi
library-dirs: $out/lib
hs-libraries: HStoml-parser-2.0.2.0-inplace
depends:
    $BASE_ID
    $TEXT_ID
    $CONTAINERS_ID
    $ARRAY_ID
    $TIME_ID
    $TRANSFORMERS_ID
    $PP_UNIT_ID
CONF

    ${ghcPkgCmd} --package-db=$out/pkgdb recache

    echo "Package database:"
    ${ghcPkgCmd} --package-db=$out/pkgdb list
  '';
}
