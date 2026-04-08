# Android Bundle vs iOS State Restoration: Should haskell-mobile Support Them?

A technical evaluation of Android's `onSaveInstanceState(Bundle)` mechanism and iOS's equivalent state restoration APIs, examining reliability, platform asymmetry, and relevance to haskell-mobile's architecture.

---

## Executive Summary

Android provides a `Bundle` mechanism that serializes key-value state when an Activity stops, surviving process death. iOS has gone through three iterations of equivalent functionality — NSCoder-based restoration, NSUserActivity scene restoration, and SwiftUI's `@SceneStorage` — each progressively less reliable than the last.

The industry consensus (2025–2026) is that these mechanisms are **lightweight optimization hints, not reliability mechanisms**. Apps should cold-start correctly from persistent storage alone. haskell-mobile's existing pattern — IORef for in-memory state, SQLite for persistence, full clear-and-rebuild rendering — already matches this modern best practice.

**Recommendation: Do not add Bundle/state restoration support to haskell-mobile.** The complexity cost is high, the iOS side is broken, and the benefit is marginal when state is properly persisted to a database.

---

## Part 1: Android's Bundle Mechanism

### 1.1 How It Works

Android's state preservation centers on the `Bundle` class — a key-value map supporting primitives and `Parcelable` objects. The lifecycle flow:

1. **Saving**: When an Activity moves to the stopped state (user presses Home, rotates screen, or system reclaims memory), the system calls `onSaveInstanceState(Bundle)` between `onPause()` and `onStop()`. The developer writes key-value pairs into the Bundle.
2. **Automatic view state**: The default implementation automatically saves transient view hierarchy state (EditText content, ListView scroll position) for any view with an `android:id`.
3. **Restoring**: When the Activity is recreated, the saved Bundle arrives in both `onCreate(Bundle?)` and `onRestoreInstanceState(Bundle)` (called after `onStart()`).
4. **Process death**: Android may kill a backgrounded app's entire process. Because `onSaveInstanceState` was already called at the stopped state, the Bundle is preserved by the system and delivered to the new process when the user returns.

### 1.2 Reliability Issues

**Size limits cause crashes.** The Binder transaction buffer is limited to ~1MB shared across all IPC for a process. Individual Bundles are practically capped at ~50KB. Exceeding the limit throws `TransactionTooLargeException`, which crashes the app with no graceful recovery path. Google recommends keeping saved state under 50KB.

**Main-thread serialization.** All Bundle serialization happens on the main thread. Complex `Parcelable` objects cause dropped frames during configuration changes. Sufficiently slow serialization can trigger ANR (Application Not Responding) dialogs.

**Process death is invisible during development.** The system only kills low-priority background processes under memory pressure. Developers rarely encounter this during testing, so the saved-state code path is effectively untested in many production apps. The "Don't keep activities" developer option exists specifically to test this, but most developers never enable it.

**Data type restrictions.** Bundles only support primitives, Strings, and `Parcelable`/`Serializable` objects. Complex object graphs, closures, and non-serializable references cannot be stored.

**Timing edge cases.** On Android versions below 12, pressing Back destroyed the Activity without calling `onSaveInstanceState`, permanently losing root Activity state. Android 12+ fixed this by always calling `onSaveInstanceState` regardless of how the Activity was closed.

### 1.3 Modern Practice (2025–2026)

Google's official recommendation is a three-tier approach:

| Mechanism | Survives Config Change | Survives Process Death | Survives App Dismissal | Speed |
|---|---|---|---|---|
| ViewModel | Yes | No | No | Fast (in-memory) |
| SavedStateHandle | Yes | Yes | No | Slow (serialization) |
| Persistent Storage (Room, DataStore) | Yes | Yes | Yes | Slow (disk I/O) |

The strategy: store full UI state in `ViewModel` for fast access. Store minimal recovery keys (IDs, query strings, scroll positions) in `SavedStateHandle`. Store application data in Room/DataStore for permanent persistence.

In Jetpack Compose, `rememberSaveable` replaces manual `onSaveInstanceState` calls, automatically bridging Compose's declarative state with the Bundle mechanism. The raw `onSaveInstanceState` / `onRestoreInstanceState` pattern is no longer best practice on its own, but the underlying Bundle mechanism remains the only system-provided way to survive process death without disk I/O.

---

## Part 2: iOS State Restoration

### 2.1 Legacy: NSCoder-Based Restoration (iOS 6–12)

Introduced in iOS 6:

1. Developers assigned restoration identifiers to view controllers and views.
2. The app delegate implemented `application(_:shouldSaveApplicationState:)` / `application(_:shouldRestoreApplicationState:)`.
3. UIKit called `encodeRestorableState(with:)` on each identified view controller, passing an `NSCoder`. On restoration, `decodeRestorableState(with:)` reconstructed state.
4. UIKit serialized the entire state graph to an on-disk archive when the app backgrounded.

**Status:** Deprecated. Does not work with UISceneDelegate-based apps (iOS 13+).

### 2.2 Modern: NSUserActivity Scene Restoration (iOS 13+)

With iOS 13's multi-window support, Apple replaced NSCoder restoration:

1. Scenes save state as `NSUserActivity` objects via `stateRestorationActivity(for:)`.
2. On reconnection, the system provides the NSUserActivity via `scene(_:restoreInteractionStateWith:)`.
3. The same NSUserActivity type is shared with Handoff, Spotlight, and Universal Links.

**The problems are severe.** Multiple Apple Developer Forum threads from iOS 13 onward report that state restoration simply stopped working. The `shouldRestoreApplicationState:` delegate method is never called. `stateRestorationActivity` returns nil despite WWDC sessions recommending it. The transition from iOS 12 to 13 lost the ability to reconnect object graphs (multiple view controllers holding references to the same model). Apple's sample code is described as "extremely simplistic" and unhelpful for real navigation hierarchies.

Starting post-iOS 26, adopting the UIScene lifecycle is mandatory (Apple TN3187), making scene-based restoration the only official path.

### 2.3 SwiftUI: @SceneStorage and @AppStorage

SwiftUI introduced property wrappers for declarative state persistence:

- **@SceneStorage**: Per-scene state (tab selection, scroll position). Destroyed when the user force-quits.
- **@AppStorage**: Wraps `UserDefaults` for app-wide preferences.

**Critical limitations of @SceneStorage:**

- Only supports simple types: String, Int, Double, Bool, URL, Data
- Apple explicitly warns against large values
- Persistence timing is "not guaranteed"
- Destroyed when the user force-quits the app
- Not secure storage

### 2.4 What iOS Developers Actually Do

Many developers have given up on system-provided restoration APIs entirely. The pragmatic approach: persist navigation state to UserDefaults, Core Data, or SwiftData, and rebuild the UI on launch. This is increasingly the standard choice.

---

## Part 3: Platform Comparison

| Dimension | Android (Bundle/SavedStateHandle) | iOS (NSUserActivity/@SceneStorage) |
|---|---|---|
| Underlying mechanism | Bundle (key-value, Parcelable) | NSCoder archive / NSUserActivity / @SceneStorage |
| Serialization | Main thread | System-managed |
| Size limit | ~50KB practical, ~1MB hard crash | No documented hard limit, "keep it small" |
| Survives process death | Yes | Yes (when it works) |
| Survives force-quit | No | No |
| Survives config change | Yes (with ViewModel) | N/A (iOS has no rotation-triggered destruction) |
| Persistence guarantee | Guaranteed at stopped state | "Not guaranteed" per Apple |
| Maturity | Well-understood, tooling exists | Frequently reported broken across iOS versions |
| Developer adoption | Universal (mandatory for process death) | Low (many skip it entirely) |

---

## Part 4: Relevance to haskell-mobile

### 4.1 Current Architecture

haskell-mobile already handles lifecycles without Bundle support:

- **Android**: `MainActivity.onCreate(Bundle savedInstanceState)` calls `onLifecycleCreate()` without passing the Bundle. The `savedInstanceState` parameter is ignored.
- **iOS**: `HaskellMobileApp` observes `scenePhase` and dispatches lifecycle events (Resume, Pause, Stop) to Haskell.
- **State**: IORef-based global state (`globalMobileApp`, `globalRenderState`) with full clear-and-rebuild rendering.
- **Persistence**: App-level SQLite (demonstrated in downstream apps), not framework-level Bundle integration.

### 4.2 What Adding Bundle Support Would Require

1. A Haskell-side serialization format for state snapshots (key-value map of primitives).
2. C FFI functions to marshal the map between Haskell and native code.
3. Android: Pass the `savedInstanceState` Bundle through JNI to the C bridge, serialize Haskell state into it on save, deserialize on restore.
4. iOS: Implement either NSUserActivity encoding in Swift or @SceneStorage bindings — both unreliable.
5. A cross-platform abstraction that papers over the fact that the iOS side may silently fail.

### 4.3 Why It Is Not Worth It

**The iOS side is broken.** Investing in cross-platform state restoration when one platform's implementation is widely reported as non-functional produces an abstraction that is unreliable by construction. haskell-mobile would need iOS-specific fallback code anyway, defeating the purpose.

**The benefit is marginal.** Bundle support only helps with one scenario: the user backgrounds the app, Android kills the process, and the user returns. With SQLite persistence, the app cold-starts into the correct state. The only difference is avoiding a brief loading moment — a minor UX concern that does not justify the complexity.

**The size limit is dangerous.** Haskell's data structures do not map naturally to Bundle's ~50KB limit. Accidentally exceeding it crashes the app. This would be a new failure mode that haskell-mobile does not currently have.

**It contradicts the industry direction.** Both Google and Apple now recommend that persistent storage (databases) own the truth, with saved-instance-state serving only as an optimization hint. haskell-mobile's architecture — SQLite for persistence, IORef for in-memory state, full rebuild on lifecycle changes — already follows this recommendation.

### 4.4 What to Do Instead

For downstream apps that need state preservation across process death:

1. **Persist to SQLite** on meaningful state changes (already the established pattern).
2. **Restore from SQLite** in the lifecycle Create handler.
3. **Use lifecycle Pause/Stop** as signals to flush pending writes.

This approach works identically on both platforms, does not have size limits, survives force-quits (which Bundle does not), and does not depend on broken iOS APIs.

---

## Conclusion

Android's Bundle mechanism is functional but constrained. iOS's equivalent is unreliable across versions. Neither is worth wrapping in a cross-platform abstraction when SQLite persistence provides a strictly superior alternative that already works in haskell-mobile's architecture. The recommendation is to document the SQLite persistence pattern for downstream apps rather than adding framework-level Bundle support.
