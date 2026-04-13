[![CI](https://img.shields.io/github/actions/workflow/status/jappeace/hatter/ci.yaml?branch=master)](https://github.com/jappeace/hatter/actions)

>  Why is a raven like a writing-desk?

![hatter](./hatter.png)

# Hatter
It's like flutter but instead of dart, haskell!

Write native mobile apps in Haskell.
This works similar to react native where we have
tight bindings on the existing UI frameworks
provided android and IOS.

This project cross-compiles a Haskell library to Android (APK) and iOS (static library / IPA),
with a thin platform-native UI layer (Kotlin for Android, Swift for iOS).
There is support for android wear and wearOS as well,
because I personally want to build apps for those. 
IOS and Android support was just a side effect.

Supports native:

+ android
+ android wearable
+ IOS
+ WearOS (IOS on wearables)


The library fully controls the UI.
This is different from say Simplex chat where they call into the library to do Haskell from dirty java/swift code.
This library should've written all swift/java code you'll ever need,
so you can focus on your sweet Haskell.

Haskell is a fantastic language for UI.
Having strong type safety around callbacks and widget's 
makes it a lot easier to write them.
I basically copied flutters' approach to encoding UI,
but in flutter it's a fair bit of guess work, 
it becomes /very/ nice in Haskell however.
I've been many times annoyed at the ~~garbage~~ languages
they keep shoving into our face for UI.
With [vibes](https://jappie.me/haskell-vibes.html) in hand I put my malice
into crafting something good.
Flutter is already pretty good, but the syntax is complex,
and it has many inherited footguns from Java.
I think I made here what flutter wanted to be.

# How to use

## Writing your app

Your app is a Haskell module with a `main :: IO (Ptr AppContext)`.
You define a `MobileApp` record and pass it to `startMobileApp`:

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Main where

import Data.IORef (newIORef, readIORef, modifyIORef')
import Data.Text qualified as Text
import Foreign.Ptr (Ptr)
import Hatter
  ( startMobileApp, MobileApp(..), AppContext
  , loggingMobileContext
  , newActionState, runActionM, createAction, Action
  )
import Hatter.Widget

main :: IO (Ptr AppContext)
main = do
  actionState <- newActionState
  counter <- newIORef (0 :: Int)
  increment <- runActionM actionState $
    createAction (modifyIORef' counter (+ 1))
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> do
        n <- readIORef counter
        pure $ Column
          [ Text TextConfig
              { tcLabel = "Count: " <> Text.pack (show n)
              , tcFontConfig = Nothing
              }
          , Button ButtonConfig
              { bcLabel      = "+"
              , bcAction     = increment
              , bcFontConfig = Nothing
              }
          ]
    , maActionState = actionState
    }
```

`maView` is called on every render cycle and returns a `Widget` tree.
Button taps (and other events) fire `Action` handles created via `runActionM`,
then the framework re-renders automatically.



### Platform bridges

The `UserState` passed to `maView` provides access to platform APIs:

| Bridge         | Functions                                                        | Comments                    |
|----------------|------------------------------------------------------------------|-----------------------------|
| Secure storage | `secureStorageWrite`, `secureStorageRead`, `secureStorageDelete` |                             |
| BLE scanning   | `startBleScan`, `stopBleScan`, `checkBleAdapter`                 | still need to do connecting |
| Location       | `startLocationUpdates`, `stopLocationUpdates`                    | gps for example             |
| Auth sessions  | `startAuthSession` (OAuth/ASWebAuthenticationSession)            |                             |
| Camera         | `startCameraSession`, `capturePhoto`, `startVideoCapture`        |                             |
| HTTP           | `performRequest`                                                 | http-client also works but this results in much smaller apks which is good for wearables                            |
| Permissions    | `requestPermission`, `checkPermission`                           |                             |

## Building for Android

Requires Nix. The build cross-compiles your Haskell to a `.so` shared library
and packages it into an APK with the Java UI layer.

### 1. Build the APK

```bash
nix-build nix/apk.nix
```

This produces `result/hatter.apk` containing both arm64-v8a and armeabi-v7a architectures.

To build with your own `Main.hs`:

```bash
nix-build nix/apk.nix --arg mainModule ./path/to/your/Main.hs
```

Or build just the shared library for a single architecture:

```bash
nix-build nix/android.nix                               # aarch64 (default)
nix-build nix/android.nix --arg androidArch '"armv7a"'   # armv7a
```

### 2. Install

```bash
adb install result/hatter.apk
```

### 3. Consumer projects with extra Haskell dependencies

If your app needs Hackage packages beyond what hatter provides,
pass them via `consumerCabalFile` or `hpkgs`:

```nix
# your-app/default.nix
let
  hatter = builtins.fetchGit {
    url = "https://github.com/jappeace/hatter.git";
    ref = "master";
  };
in import "${hatter}/nix/apk.nix" {
  mainModule = ./src/Main.hs;
  # Option A: point to your .cabal file (uses IFD to extract deps)
  consumerCabalFile = ./your-app.cabal;
  # Option B: override haskellPackages directly
  # hpkgs = self: super: { aeson = self.callHackage "aeson" "2.2.1.0" {}; };
}
```

### How it works under the hood

The Java activity (`HatterActivity`) loads the `.so` via `System.loadLibrary`,
which triggers `JNI_OnLoad` in `cbits/jni_bridge.c`. That initializes the GHC RTS,
runs your Haskell `main`, and stores the returned `AppContext` pointer.
When `onCreate` fires, Java calls `renderUI` through JNI, which invokes your `maView`
and the framework translates the `Widget` tree into Android `View` calls.

You never need to write Java — `HatterActivity` handles all the native UI,
permissions, camera, location, etc. Your consumer app's `MainActivity` just extends it:

```java
package com.example.myapp;
import me.jappie.hatter.HatterActivity;
public class MainActivity extends HatterActivity {}
```

## Building for iOS

Requires macOS with Nix. The build produces a static `.a` library that links into
an Xcode project via a Swift bridge.

### 1. Build the static library

```bash
nix-build nix/ios.nix
```

This produces `result/lib/libHatter.a` and headers in `result/include/`.

To build with your own `Main.hs`:

```bash
nix-build nix/ios.nix --arg mainModule ./path/to/your/Main.hs
```

### 2. Set up the Xcode project

Stage the library and headers, then generate the Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
mkdir -p ios/lib ios/include
cp result/lib/libHatter.a ios/lib/
cp result/include/*.h ios/include/

nix-shell -p xcodegen --run "cd ios && xcodegen generate"
open ios/Hatter.xcodeproj
```

The `ios/project.yml` configures the bridging header, library search paths,
and framework dependencies automatically.

### 3. Build and run

Configure signing in Xcode (team, bundle ID, provisioning profile), then
build and run on a device or simulator.

### How it works under the hood

The Swift bridge (`ios/Hatter/HaskellBridge.swift`) calls `hs_init` and
`haskellRunMain` to boot the GHC RTS and run your Haskell `main`.
It then sets up all the platform bridges (permissions, camera, location, etc.)
and calls `haskellRenderUI` when SwiftUI requests a view update.

The bridging header (`Hatter-Bridging-Header.h`) exposes the C FFI functions
to Swift. The `project.yml` links against the required system frameworks
(CoreLocation, CoreBluetooth, AVFoundation, WebKit, etc.).

### Consumer iOS projects

Copy the `ios/` directory as a starting point for your app.
The key files are:

| File | Purpose |
|------|---------|
| `HaskellBridge.swift` | Boots GHC RTS, dispatches UI events |
| `HatterApp.swift` | SwiftUI `@main` entry point |
| `ContentView.swift` | SwiftUI view that calls `HaskellBridge.renderUI()` |
| `Hatter-Bridging-Header.h` | C header imports for Swift |
| `project.yml` | XcodeGen spec with signing, frameworks, search paths |

## Building for watchOS

```bash
nix-build nix/watchos.nix
```

Works the same as iOS — produces a static library for watchOS.
The `watchos/` directory contains the WatchKit app structure.

## Desktop development

For fast iteration, build and test natively:

```bash
nix-shell
cabal build all
cabal test all
```

The desktop build uses stub C bridges that simulate platform responses
(e.g. permissions always granted, location returns fixed coordinates).
This lets you develop and test your app logic without a device.

## CI

Five CI jobs run on every push:

| Job | Platform | What it does |
|-----|----------|--------------|
| `nix-build` | Linux | Full nix-build + cabal test |
| `android` | Linux | Cross-compile aarch64, build APK |
| `android-armv7a-emulator` | Linux | Cross-compile armv7a, run in emulator |
| `ios` | macOS | Cross-compile to iOS static lib |
| `watchos` | macOS | Cross-compile to watchOS static lib |
