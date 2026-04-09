[![CI](https://img.shields.io/github/actions/workflow/status/jappeace/haskell-mobile/ci.yaml?branch=master)](https://github.com/jappeace/haskell-mobile/actions)

>  To see a need and wait to be asked, is to already refuse. 

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

## Architecture

### Boot Sequence

Platform builds produce a **library** (`.so` on Android, `.a` on iOS), not an executable.
The user writes a `main :: IO (Ptr AppContext)` that calls `startMobileApp` — no
`foreign export ccall` needed. The C bridge runs it using the GHC RTS API and
captures the returned context pointer.

#### Android

`JNI_OnLoad` (`cbits/jni_bridge.c`) — Android's JVM calls this automatically when
`System.loadLibrary("haskellmobile")` loads the `.so`. It runs:

```c
hs_init(NULL, NULL);               // 1. start GHC runtime
g_ctx = haskellRunMain();          // 2. run user's main, get context pointer
```

#### iOS

Same sequence. The Swift bridge (`ios/HaskellMobile/HaskellBridge.swift`) calls:

```swift
hs_init(nil, nil)
context = haskellRunMain()
```

The `.a` static library is linked directly into the Xcode project —
Swift calls the C functions without JNI.

#### What each step does

1. **`hs_init`** — Starts the GHC runtime (GC, thread scheduler, IO manager).
   Does **not** call `main`.

2. **`haskellRunMain`** (`cbits/run_main.c`) — A C function that evaluates the user's
   Haskell `main` via the GHC RTS API and captures the return value:
   ```c
   Capability *cap = rts_lock();
   HaskellObj result;
   rts_evalIO(&cap, &ZCMain_main_closure, &result);
   void *ctx = rts_getPtr(result);
   rts_unlock(cap);
   return ctx;
   ```
   GHC compiles `Main.main` into a closure called `ZCMain_main_closure` (Z-encoded
   symbol for `:Main.main`). The user's `main` calls `startMobileApp`, which creates
   an `AppContext` (bundling the `MobileApp`'s callbacks, render state, permission
   state, and view function) and returns it as a `StablePtr`.

After boot, the platform calls FFI exports (`haskellRenderUI`, `haskellOnUIEvent`,
`haskellOnLifecycle`) passing the context pointer. All state lives in the `AppContext` —
no global mutable variables.

#### Desktop (executable)

`app/Main.hs` is a desktop demo. GHC's generated C `main()` stub calls `hs_main`,
which does `hs_init` + `rts_evalLazyIO(main)` + `hs_exit` automatically. The user's
`main` calls `startMobileApp`, then simulates lifecycle events using the returned context.

`app/MobileMain.hs` is the mobile entry point for the demo — it's compiled into the
`.so`/`.a` by the nix build scripts. Downstream users write their own `Main.hs`.

### AppContext

The `AppContext` (`src/HaskellMobile/AppContext.hs`) bundles all per-session state:

```haskell
data MobileApp = MobileApp
  { maContext :: MobileContext    -- lifecycle callbacks
  , maView    :: UserState -> IO Widget  -- returns the current UI tree
  }

data AppContext = AppContext
  { acMobileContext   :: MobileContext
  , acRenderState     :: RenderState
  , acPermissionState :: PermissionState
  , acViewFunction    :: IORef (UserState -> IO Widget)
  }

startMobileApp :: MobileApp -> IO (Ptr AppContext)
```

All FFI entry points (`haskellRenderUI`, `haskellOnUIEvent`, `haskellOnLifecycle`)
receive the `AppContext` pointer and read all state from it.

### Rendering Cycle

When native code calls `renderUI`:

1. `haskellRenderUI` reads the view function from `AppContext`, calls it to get the `Widget` tree
2. `renderWidget` (`src/HaskellMobile/Render.hs`) clears the screen, walks the tree
   calling `Bridge.createNode` / `Bridge.addChild` / `Bridge.setHandler`, and registers
   callbacks (click handlers, text change handlers) in `IntMap`s keyed by callback ID
3. When the user taps a button, native code calls `haskellOnUIEvent` with a callback ID,
   which looks up and fires the `IO ()` action from the `IntMap`, then re-renders

Text input changes go through `haskellOnUITextChange` instead, which dispatches the
text callback but does **not** re-render (to avoid cursor/flicker issues on Android).

### How User Code Plugs In

A downstream user provides two things:

1. **A `MobileApp` value** — their `maView` returns the widget tree, their `maContext`
   handles lifecycle events.

2. **A `Main.hs`** with a `main :: IO (Ptr AppContext)` that calls `startMobileApp`. No
   `foreign export ccall` needed — `cbits/run_main.c` calls it via the GHC RTS API.
   The nix build scripts accept the user's Main.hs as the `mainModule` parameter.

Example user `Main.hs`:

```haskell
module Main where

import Foreign.Ptr (Ptr)
import HaskellMobile (startMobileApp, AppContext)
import MyApp (myApp)  -- user's MobileApp

main :: IO (Ptr AppContext)
main = startMobileApp myApp
```

### Managing App State

The library owns all state through the `AppContext` — there are no global mutable
variables. If your app needs its own mutable state (e.g. a counter, form fields,
a model), create an `IORef` (or `TVar`, `MVar`, etc.) when you build your
`MobileApp` and close over it in `maView` and your button callbacks:

```haskell
import Data.IORef (newIORef, readIORef, modifyIORef')

myApp :: IO MobileApp
myApp = do
  counter <- newIORef (0 :: Int)
  pure MobileApp
    { maContext = loggingMobileContext
    , maView = \_userState -> do
        n <- readIORef counter
        pure $ Column
          [ Text TextConfig { tcLabel = "Count: " <> pack (show n), tcFontConfig = Nothing }
          , Button ButtonConfig
              { bcLabel = "+"
              , bcAction = modifyIORef' counter (+ 1)
              , bcFontConfig = Nothing
              }
          ]
    }
```

The `IORef` lives as long as your `MobileApp` does (i.e. the lifetime of the
`AppContext`). Each context is independent, so tests can create isolated
instances without shared mutable state.

Build for Android with:

```nix
import ./nix/android.nix { mainModule = ./my-app/Main.hs; }
```

```
Android: JNI_OnLoad -> hs_init -> haskellRunMain -> main -> startMobileApp(app) -> Ptr AppContext
                                                                    |
                                                      bundles MobileApp into AppContext
                                                                    |
         renderUI  -> haskellRenderUI(ctx)  -> acViewFunction -> Widget tree -> Bridge
         onClick   -> haskellOnUIEvent(ctx) -> IntMap lookup -> fire IO action -> re-render
```

### Key Files

| File | Role |
|------|------|
| `app/Main.hs` | Desktop demo executable — calls `startMobileApp` and simulates lifecycle |
| `app/MobileMain.hs` | Demo mobile entry point — a `main :: IO (Ptr AppContext)`. Downstream users write their own |
| `cbits/run_main.c` | Calls `rts_evalIO(&ZCMain_main_closure)` — runs the user's Haskell main and captures the returned context pointer |
| `src/HaskellMobile.hs` | FFI exports: `haskellGreet`, `haskellRenderUI`, `haskellOnUIEvent`, `haskellOnUITextChange`, `startMobileApp` |
| `src/HaskellMobile/AppContext.hs` | `AppContext` record, `newAppContext`, `derefAppContext` |
| `src/HaskellMobile/Types.hs` | `MobileApp` record and `UserState` type |
| `src/HaskellMobile/App.hs` | Default app (counter demo) — replace with your own |
| `src/HaskellMobile/Lifecycle.hs` | `LifecycleEvent` enum, `MobileContext`, `haskellOnLifecycle` FFI export |
| `src/HaskellMobile/Widget.hs` | `Widget` ADT: `Text`, `Button`, `TextInput`, `Row`, `Column` |
| `src/HaskellMobile/UIBridge.hs` | Haskell FFI imports for the C UI bridge (`createNode`, `setRoot`, etc.) |
| `src/HaskellMobile/Render.hs` | Rendering engine: walks `Widget` tree, issues bridge calls, manages callback registries |
| `cbits/jni_bridge.c` | Android JNI entry points — calls Haskell FFI exports |
| `cbits/ui_bridge.c` | C-side UI bridge (callback storage, stub implementations for desktop) |
| `cbits/ui_bridge_android.c` | Android-specific UI bridge (calls back into Java via JNI) |
| `cbits/platform_log.c` | Platform logging (`__android_log_print` / `os_log` / `fprintf(stderr)`) |
| `include/HaskellMobile.h` | C header for all Haskell FFI exports |
| `include/UIBridge.h` | C header for the UI bridge callbacks |

# Roadmap

+ Test out lifecycles.
  + Need logging support in respective frameworks, make sure they get triggered.
+ Figure out how to do UI
  + need to be able to register callbacks on events, eg onButtonClick
  + tranistion between UI's?
