# Change log for hatter

## Version 0.2.0

### Breaking changes

- Platform-specific types are no longer re-exported from `Hatter`.
  Import them from their own modules instead:
  `Hatter.Permission`, `Hatter.SecureStorage`, `Hatter.Ble`,
  `Hatter.Dialog`, `Hatter.Location`, `Hatter.AuthSession`,
  `Hatter.Camera`, `Hatter.BottomSheet`, `Hatter.Http`,
  `Hatter.NetworkStatus`, `Hatter.Locale`, `Hatter.I18n`,
  `Hatter.FilesDir`.
- `AppContext`, `derefAppContext`, `freeAppContext`, and `newAppContext`
  moved to `Hatter.AppContext` (no longer re-exported from `Hatter`).
- `newMobileContext` and `freeMobileContext` are no longer re-exported
  from `Hatter` (available from `Hatter.Lifecycle`).
- FFI dispatch functions (`haskellOnPermissionResult`,
  `haskellOnBleScanResult`, etc.) are no longer in the Haskell export
  list.  They remain available as C symbols via `foreign export ccall`.
- Removed `haskellGreet` (dead hello-world smoke test, unused by any
  app code).

### Added

- `Hatter.PlatformSignIn` — native platform sign-in (Sign in with Apple
  on iOS/watchOS, Google identity via AccountManager on Android/Wear OS).
- `Hatter` module now has a haddock header with overview, usage example,
  and a directory of platform subsystem modules.
- Export list organised under haddock section headers: App setup, Widget,
  Actions, Animation, Lifecycle, Error handling, Internal.
- Full `Hatter.Widget` re-exports in the main module: `WidgetStyle`,
  `defaultStyle`, `Color`, `colorFromText`, `colorToHex`, `ImageConfig`,
  `ImageSource`, `ResourceName`, `ScaleType`, `TextAlignment`,
  `TextInputConfig`, `InputType`, `WebViewConfig`, `MapViewConfig`,
  `button`, `text`.

## Version 0.1.0

Initial release of hatter (renamed from haskell-mobile).
