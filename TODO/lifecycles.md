# Deferred Lifecycle Events

Lifecycle events not yet implemented due to lack of cross-platform equivalents
or requiring platform-specific APIs beyond the current scope.

## Android-Only (deferred)

| Event | Reason |
|-------|--------|
| `onRestart` | No iOS equivalent; rare use case (Start already covers re-entering foreground) |
| `onSaveInstanceState` | Android-specific state persistence; iOS uses different restoration APIs |
| `onRestoreInstanceState` | Counterpart to onSaveInstanceState; same reasoning |
| `onConfigurationChanged` | Android-specific (rotation, locale change); iOS handles via SwiftUI environment |
| `onTrimMemory(level)` | Granular memory pressure with level parameter; iOS equivalent (didReceiveMemoryWarning) is a separate API |

## iOS-Only (deferred)

| Event | Reason |
|-------|--------|
| `viewWillAppear` / `viewDidAppear` | UIKit ViewController lifecycle, not available in SwiftUI without bridging |
| `viewWillDisappear` / `viewDidDisappear` | Same as above |
| `viewIsAppearing` (iOS 17+) | UIKit-only, requires iOS 17 minimum |
| `applicationWillTerminate` | Requires UIApplicationDelegate; SwiftUI has no direct equivalent |
| `didReceiveMemoryWarning` | Requires NotificationCenter subscription (`.UIApplication.didReceiveMemoryWarningNotification`) |
| State restoration | iOS uses NSUserActivity / scene-based state restoration, very different model from Android |

## Currently Implemented

| Event | Code | Android | iOS |
|-------|------|---------|-----|
| Create | 0 | `onCreate` | App `init()` |
| Start | 1 | `onStart` | (not fired) |
| Resume | 2 | `onResume` | `.active` |
| Pause | 3 | `onPause` | `.inactive` |
| Stop | 4 | `onStop` | `.background` |
| Destroy | 5 | `onDestroy` | (not fired) |
| LowMemory | 6 | `onLowMemory` | (not fired) |

iOS fires Create/Resume/Pause/Stop. Start/Destroy/LowMemory are Android-only in practice.
