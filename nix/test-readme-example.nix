{ sources ? import ../npins }:
let
  pkgs = import sources.nixpkgs {};
  hpkgs = import ./hpkgs.nix { inherit pkgs; };
  readme = ../Readme.md;

  # Extract the first ```haskell block after "## Writing your app"
  extractedMain = pkgs.runCommand "extract-readme-main" {} ''
    ${pkgs.gawk}/bin/awk '
      /^## Writing your app/ { found_section=1 }
      found_section && /^```haskell/ { capture=1; next }
      capture && /^```/ { capture=0 }
      capture { print }
    ' ${readme} > $out

    if [ ! -s "$out" ]; then
      echo "ERROR: Failed to extract Haskell code block from Readme.md"
      echo "Expected a \`\`\`haskell fenced block under '## Writing your app'"
      exit 1
    fi
  '';
in
  pkgs.runCommand "readme-example-typecheck" {
    nativeBuildInputs = [
      (hpkgs.ghcWithPackages (p: [ p.haskell-mobile-project ]))
    ];
  } ''
    cp ${extractedMain} Main.hs
    ghc -fno-code -c Main.hs
    touch $out
  ''
