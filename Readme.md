[![CI](https://img.shields.io/github/actions/workflow/status/jappeace/haskell-mobile/ci.yaml?branch=master)](https://github.com/jappeace/haskell-mobile/actions)

# Haskell Mobile

Write mobile apps in Haskell.
This project cross-compiles a Haskell library to Android (APK) and iOS (static library / IPA),
with a thin platform-native UI layer (Kotlin for Android, Swift for iOS).

## Building

### Native (desktop)

Enter the Nix shell and use cabal:

```bash
nix-shell
cabal build all
cabal test all
```

Or use the makefile shortcuts (`make build`, `make test`, `make ghcid`).

### Android APK

```bash
nix-build nix/android.nix   # cross-compiled Haskell library
nix-build nix/apk.nix       # full APK
```

The APK is written to `result/haskell-mobile.apk`.

### iOS static library

Requires macOS (same ISA as iOS aarch64):

```bash
nix-build nix/ios.nix
```

Produces `result/lib/libHaskellMobile.a` and `result/include/HaskellMobile.h`.

### iOS app (local dev)

After building the static library, generate an Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
# Stage the Haskell library where the Xcode project expects it
mkdir -p ios/lib ios/include
cp result/lib/libHaskellMobile.a ios/lib/
cp result/include/HaskellMobile.h ios/include/

# Generate and open
nix-shell -p xcodegen --run "cd ios && xcodegen generate"
open ios/HaskellMobile.xcodeproj
```

Configure signing in Xcode (team, bundle ID, provisioning profile), then build and run.

## Installing

### Android

```bash
adb install result/haskell-mobile.apk
```

### iOS

Use Xcode to deploy to a connected device, or download the IPA artifact from the
[CI Actions page](https://github.com/jappeace/haskell-mobile/actions) (master builds only, when signing secrets are configured).

## CI

The GitHub Actions workflow runs four jobs:

| Job | Platform | What it does |
|-----|----------|--------------|
| `nix` | Linux | `nix-build` + `nix-shell` smoke test |
| `android` | Linux | Cross-compile to Android, build APK (master) |
| `ios` | macOS | Cross-compile to iOS static lib, build IPA if signing secrets are set (master) |
| `cabal` | Linux/macOS/Windows | GHC 9.6 / 9.8 / 9.10 / 9.12 matrix build + tests |

### iOS signing secrets

The IPA build is conditional: without secrets, CI only builds the static library.
To enable IPA builds, add these repository secrets:

| Secret | Description |
|--------|-------------|
| `APPLE_CERTIFICATE_BASE64` | Base64-encoded `.p12` distribution certificate |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the `.p12` file |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Base64-encoded `.mobileprovision` file |
| `APPLE_TEAM_ID` | Apple Developer Team ID |

Generate the base64 values with:

```bash
base64 -i Certificates.p12 | pbcopy
base64 -i App.mobileprovision | pbcopy
```
