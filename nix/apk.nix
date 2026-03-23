{ sources ? import ../npins }:
let
  pkgs = import sources.nixpkgs {
    config.allowUnfree = true;
    config.android_sdk.accept_license = true;
  };

  sharedLib = import ./android.nix { inherit sources; };

  androidComposition = pkgs.androidenv.composeAndroidPackages {
    buildToolsVersions = [ "34.0.0" ];
    platformVersions = [ "34" ];
    includeNDK = false;
  };

  androidSdk = androidComposition.androidsdk;
  buildTools = "${androidSdk}/libexec/android-sdk/build-tools/34.0.0";
  platform = "${androidSdk}/libexec/android-sdk/platforms/android-34";

in pkgs.stdenv.mkDerivation {
  name = "haskell-mobile-apk";

  src = ../android;

  nativeBuildInputs = with pkgs; [
    jdk17_headless
    zip
    unzip
  ];

  buildPhase = ''
    export HOME=$TMPDIR

    echo "=== Step 1: Compile resources with aapt2 ==="
    mkdir -p compiled_res
    ${buildTools}/aapt2 compile \
      --dir res \
      -o compiled_res/

    echo "=== Step 2: Link resources with aapt2 ==="
    mkdir -p gen
    ${buildTools}/aapt2 link \
      -I ${platform}/android.jar \
      --manifest AndroidManifest.xml \
      --java gen \
      -o base.apk \
      compiled_res/*.flat

    echo "=== Step 3: Compile Java sources ==="
    mkdir -p classes

    # Find R.java
    find gen -name "*.java" -print

    # Compile R.java and MainActivity.java
    javac \
      -source 11 -target 11 \
      -classpath ${platform}/android.jar \
      -d classes \
      gen/me/jappie/haskellmobile/R.java \
      java/me/jappie/haskellmobile/MainActivity.java

    echo "=== Step 4: Convert to DEX ==="
    mkdir -p dex_out
    ${buildTools}/d8 \
      --min-api 26 \
      --output dex_out \
      $(find classes -name "*.class")

    echo "=== Step 5: Build APK ==="
    # Start from the base APK (has resources + manifest)
    cp base.apk unsigned.apk

    # Add DEX file
    cd dex_out
    zip -j ../unsigned.apk classes.dex
    cd ..

    # Add native libraries (main .so + runtime dependencies like libgmp, libffi)
    mkdir -p lib/arm64-v8a
    cp ${sharedLib}/lib/arm64-v8a/*.so lib/arm64-v8a/
    zip -r unsigned.apk lib/

    echo "=== Step 6: Zipalign ==="
    ${buildTools}/zipalign -f 4 unsigned.apk aligned.apk

    echo "=== Step 7: Sign APK ==="
    # Generate a debug keystore
    keytool -genkeypair \
      -keystore debug.keystore \
      -storepass android \
      -keypass android \
      -alias debug \
      -keyalg RSA \
      -keysize 2048 \
      -validity 10000 \
      -dname "CN=Debug, OU=Debug, O=Debug, L=Debug, ST=Debug, C=US"

    ${buildTools}/apksigner sign \
      --ks debug.keystore \
      --ks-pass pass:android \
      --key-pass pass:android \
      --ks-key-alias debug \
      --out haskell-mobile.apk \
      aligned.apk
  '';

  installPhase = ''
    mkdir -p $out
    cp haskell-mobile.apk $out/
  '';
}
