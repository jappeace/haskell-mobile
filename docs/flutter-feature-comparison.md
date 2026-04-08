# Flutter Feature Comparison with haskell-mobile

A feature-by-feature comparison of Flutter's capabilities against what haskell-mobile currently supports. This serves as both a gap analysis and a roadmap reference.

---

## Feature Matrix

| # | Feature Area | Flutter | haskell-mobile | Gap |
|---|---|---|---|---|
| 1 | [Widgets (basic)](#1-basic-widgets) | ~180 built-in widgets | 8 widget types | Large |
| 2 | [Layout system](#2-layout-system) | Constraint-based, Flex, Stack, Grid, Sliver | Column, Row, ScrollView | Large |
| 3 | [Text rendering](#3-text-rendering) | Rich text, spans, fonts, selectable | Plain text with font size and color | Medium |
| 4 | [Input handling](#4-input-handling) | Text, gestures, focus, keyboard shortcuts | Button tap, text input (text/numeric) | Large |
| 5 | [Scrolling and lists](#5-scrolling-and-lists) | ListView, GridView, Slivers, lazy loading | ScrollView (full rebuild, no lazy) | Large |
| 6 | [Navigation and routing](#6-navigation-and-routing) | Navigator 2.0, named routes, deep links | None (manual view switching) | Large |
| 7 | [Animation](#7-animation) | Implicit, explicit, hero, physics-based | None | Full gap |
| 8 | [Theming and styling](#8-theming-and-styling) | Material 3, Cupertino, full theme system | Padding, text/bg color, font size, alignment | Large |
| 9 | [Images and media](#9-images-and-media) | Network images, caching, SVG, video, audio | Resource, raw bytes, file path (static) | Large |
| 10 | [State management](#10-state-management) | setState, InheritedWidget, Provider, Riverpod, Bloc | IORef + full re-render | Medium |
| 11 | [Platform integration](#11-platform-integration) | Platform channels, Dart FFI, 350+ pub.dev plugins | Permissions, lifecycle, locale, logging | Large |
| 12 | [Accessibility](#12-accessibility) | Semantics tree, screen reader labels, roles | None (relies on native widget defaults) | Large |
| 13 | [Internationalization](#13-internationalization) | intl, ARB files, plural/gender, date/number formatting | Key-value translation with locale fallback | Medium |
| 14 | [Testing](#14-testing) | Widget tests, golden tests, integration tests, driver | Unit tests, FFI dispatch tests, demo apps | Medium |
| 15 | [Incremental rendering](#15-incremental-rendering) | Element tree diffing, repaint boundaries, retained layers | Full clear-and-rebuild every frame | Large |
| 16 | [Platform targets](#16-platform-targets) | Android, iOS, web, macOS, Windows, Linux | Android, iOS, watchOS, desktop (test) | Small |
| 17 | [Hot reload](#17-hot-reload) | Sub-second with state preservation | None (recompile + redeploy) | Large |
| 18 | [Custom painting](#18-custom-painting) | Canvas API, CustomPainter, shaders | None | Full gap |
| 19 | [Forms and validation](#19-forms-and-validation) | Form widget, validators, controllers | TextInput with onChange callback | Large |
| 20 | [Networking](#20-networking) | http, dio, web sockets, gRPC | None in framework (user brings own) | N/A |

---

## Detailed Comparison

### 1. Basic Widgets

**Flutter** provides ~180 built-in widgets organized into categories: layout, text, input, display, scrolling, dialog, navigation, and platform-adaptive (Material and Cupertino). Core examples: `Container`, `Text`, `Image`, `Icon`, `Card`, `Chip`, `Divider`, `Checkbox`, `Radio`, `Switch`, `Slider`, `DropdownButton`, `PopupMenu`, `BottomSheet`, `Dialog`, `Scaffold`, `AppBar`, `TabBar`, `Drawer`, `FloatingActionButton`.

**haskell-mobile** has 8 widget constructors:

| Widget | Description |
|---|---|
| `Text` | Read-only label with optional `FontConfig` |
| `Button` | Tappable with label + `IO ()` handler |
| `TextInput` | Controlled text field (text or numeric keyboard) |
| `Column` | Vertical layout container |
| `Row` | Horizontal layout container |
| `ScrollView` | Vertical scrolling container |
| `Image` | From resource name, raw bytes, or file path |
| `Styled` | Wrapper applying `WidgetStyle` to any widget |

**Gap**: Most of Flutter's widget catalog has no equivalent. Missing: checkboxes, radio buttons, switches, sliders, dropdowns, dialogs, bottom sheets, cards, dividers, icons, progress indicators, chips, tooltips, snackbars, app bars, tabs, drawers, FABs.

---

### 2. Layout System

**Flutter** uses a constraint-based layout where parent widgets pass `BoxConstraints` (min/max width and height) down to children, children report their size back up, and parents position children. Layout containers include:

- `Row`, `Column` -- flex-based linear layout with `mainAxisAlignment`, `crossAxisAlignment`, `flex`, `Expanded`, `Flexible`, `Spacer`
- `Stack` -- overlapping children with `Positioned` for absolute placement
- `Wrap` -- like Row/Column but wraps to next line when full
- `GridView` -- 2D grid with fixed or dynamic column counts
- `Table` -- explicit row/column table layout
- `CustomMultiChildLayout` -- arbitrary positioning via delegate
- `ConstrainedBox`, `SizedBox`, `FractionallySizedBox` -- size constraints
- `Padding`, `Center`, `Align` -- positioning modifiers
- `AspectRatio`, `FittedBox`, `IntrinsicWidth/Height` -- sizing utilities

**haskell-mobile** has:

- `Column [Widget]` -- vertical stacking
- `Row [Widget]` -- horizontal stacking
- `ScrollView [Widget]` -- vertical scrolling
- `wsPadding` in `WidgetStyle` -- uniform padding

No flex weights, no alignment control on containers, no stacking/overlapping, no grid, no explicit sizing constraints, no wrapping.

**Gap**: No `Expanded`/`Flexible` equivalents, no `Stack`, no `Grid`, no alignment on Row/Column, no explicit size constraints, no aspect ratio control.

---

### 3. Text Rendering

**Flutter** supports:
- `Text` with `TextStyle` (font family, size, weight, style, color, decoration, letter spacing, word spacing, height, shadows, background)
- `RichText` with `TextSpan` tree for mixed-style inline text
- `SelectableText` for copy-paste
- `Text.rich` shorthand
- Text overflow modes (ellipsis, fade, clip)
- Maximum lines
- Custom fonts loaded from assets
- Right-to-left text support

**haskell-mobile** supports:
- `Text TextConfig` with `FontConfig` containing `fontSize`
- Text color via `wsTextColor` in `WidgetStyle`
- Text alignment (`AlignStart`, `AlignCenter`, `AlignEnd`)

**Gap**: No rich text / mixed-style spans, no font weight/style/family selection, no text overflow handling, no selectable text, no text decoration, no custom fonts.

---

### 4. Input Handling

**Flutter** supports:
- `TextField` / `TextFormField` with full control (selection, cursor, input formatting, obscuring)
- `GestureDetector` (tap, double-tap, long-press, pan, scale, drag)
- `InkWell` / `InkResponse` (material ripple on tap)
- `Dismissible` (swipe-to-dismiss)
- `Draggable` / `DragTarget`
- `FocusNode` / `FocusScope` for keyboard focus management
- `RawKeyboardListener` / `KeyboardListener`
- `Listener` (raw pointer events)
- `MouseRegion` (hover, enter, exit)
- `AbsorbPointer` / `IgnorePointer` (event blocking)

**haskell-mobile** supports:
- `Button` with `IO ()` click callback
- `TextInput` with `tiOnChange :: Text -> IO ()` callback, controlled value, hint text
- Two keyboard types: `InputText`, `InputNumber`

**Gap**: No gesture recognition (swipe, long-press, drag, scale), no focus management, no keyboard event handling, no pointer/hover events, no input formatting or masking.

---

### 5. Scrolling and Lists

**Flutter** supports:
- `ListView` -- lazy-loading scrollable list (only builds visible items)
- `ListView.builder` -- on-demand item construction from index
- `GridView` / `GridView.builder` -- 2D lazy grid
- `CustomScrollView` with `Slivers` -- composable scrolling
- `SliverList`, `SliverGrid`, `SliverAppBar`, `SliverToBoxAdapter`
- `PageView` -- horizontal page swiping
- `NestedScrollView` -- coordinated scrolling
- `ReorderableListView` -- drag-to-reorder
- `RefreshIndicator` -- pull-to-refresh
- Scroll controllers, scroll physics, scroll notifications
- Estimated total scroll extent for scroll bar accuracy

**haskell-mobile** supports:
- `ScrollView [Widget]` -- vertically scrollable container with all children built eagerly

**Gap**: No lazy list construction (all items built on every render), no grid scrolling, no horizontal scrolling, no scroll controllers, no pull-to-refresh, no reorderable lists, no slivers, no pagination.

---

### 6. Navigation and Routing

**Flutter** supports:
- `Navigator` with push/pop stack
- `Navigator 2.0` declarative API with `Router`, `RouteInformationParser`, `RouterDelegate`
- Named routes with arguments
- Deep linking from URLs
- `Hero` animations across routes
- Bottom navigation bars, tab bars, drawers
- `go_router` (most popular declarative router)
- Dialog/modal/bottom sheet presentation
- `WillPopScope` / `PopScope` for back-button interception

**haskell-mobile** has no navigation system. The app is a single `maView :: UserState -> IO Widget` function. To simulate multiple screens, the user would need to manage screen state manually and branch in the view function.

**Gap**: No navigation stack, no route management, no deep linking, no screen transitions, no modal presentation.

---

### 7. Animation

**Flutter** supports:
- **Implicit animations**: `AnimatedContainer`, `AnimatedOpacity`, `AnimatedPositioned`, `AnimatedCrossFade`, `AnimatedSwitcher` (~20 implicit animation widgets)
- **Explicit animations**: `AnimationController`, `Tween`, `CurvedAnimation`, `AnimatedBuilder`
- **Hero animations**: Shared element transitions across routes
- **Physics-based animations**: `SpringSimulation`, `FrictionSimulation`, `GravitySimulation`
- **Staggered animations**: Sequential/overlapping animation sequences
- **Custom animation curves**: 40+ built-in curves (ease, bounce, elastic, etc.)
- **Lottie** support via plugin for After Effects animations
- **Rive** support for interactive vector animations
- Frame-accurate vsync-driven animation at 60/120fps

**haskell-mobile** has no animation support. The rendering model is full clear-and-rebuild on each event-triggered re-render. There is no concept of frame-by-frame updates, interpolation, or timed transitions.

**Gap**: Complete. No animation of any kind.

---

### 8. Theming and Styling

**Flutter** supports:
- `ThemeData` with 50+ configurable properties (color scheme, typography, shape, elevation, component themes)
- Material Design 3 with dynamic color
- Cupertino (iOS-style) theme
- `Theme.of(context)` for inherited theme access
- Dark mode / light mode switching
- Custom component themes (`ElevatedButtonTheme`, `InputDecorationTheme`, etc.)
- `TextTheme` with predefined type scale
- `ColorScheme` with semantic color roles
- Platform-adaptive styling (`Platform.isIOS`)

**haskell-mobile** supports via `WidgetStyle`:
- `wsPadding :: Double` -- uniform padding
- `wsTextAlign :: TextAlignment` -- start, center, end
- `wsTextColor :: Color` -- 8-bit RGBA
- `wsBackgroundColor :: Color` -- 8-bit RGBA
- `FontConfig` with `fontSize :: Double`
- `Color` type with hex parsing (`colorFromText`)

Applied via `Styled WidgetStyle Widget` wrapper.

**Gap**: No theme inheritance, no dark mode, no elevation/shadow, no border/radius, no margin, no per-component themes, no typography scale, no font weight/family.

---

### 9. Images and Media

**Flutter** supports:
- `Image.network` -- load from URL with placeholder and error handling
- `Image.asset` -- load from app bundle
- `Image.file` -- load from filesystem
- `Image.memory` -- load from bytes
- Image caching (in-memory LRU cache)
- SVG rendering (via `flutter_svg`)
- Video playback (`video_player`)
- Audio playback (`audioplayers`, `just_audio`)
- Camera (`camera` plugin)
- Animated GIFs
- `BoxFit` modes (contain, cover, fill, fitWidth, fitHeight, none, scaleDown)
- `FilterQuality` for sampling
- `ColorFilter`, `ImageFilter` for effects

**haskell-mobile** supports via `ImageConfig`:
- `ImageResource Text` -- platform bundled resource by name
- `ImageData ByteString` -- raw PNG/JPEG bytes
- `ImageFile Text` -- file path on disk
- `ScaleType`: `ScaleFit`, `ScaleFill`, `ScaleNone`

**Gap**: No network image loading, no image caching, no SVG, no video, no audio, no camera, no animated images, no image filters.

---

### 10. State Management

**Flutter** built-in:
- `setState()` -- triggers rebuild of the `StatefulWidget`'s subtree only
- `InheritedWidget` -- O(1) ancestor data lookup, selective rebuild via `updateShouldNotify`
- `ValueNotifier` / `ChangeNotifier` -- observable pattern
- `StreamBuilder` / `FutureBuilder` -- async data binding

Popular packages: Provider, Riverpod, Bloc/Cubit, GetX, MobX, Redux.

Flutter's key advantage: incremental rebuild. Only the dirty subtree is rebuilt; unchanged subtrees are skipped via element identity matching.

**haskell-mobile**:
- `IORef (Maybe MobileApp)` stores the registered app
- `RenderState` tracks callback registries (fresh `IntMap` each render)
- Full re-render of entire widget tree on every event
- User manages their own state via closures in `IO`

The model is simple and correct, but every render rebuilds the entire widget tree and sends the full tree across FFI. There is no diffing or incremental update.

**Gap**: No incremental rendering (full tree rebuild every time), no built-in observable/reactive patterns, no scoped rebuilds.

---

### 11. Platform Integration

**Flutter** provides:
- Platform channels (`MethodChannel`, `EventChannel`) for bidirectional native communication
- Dart FFI for direct C library binding
- 350+ first-party and community plugins on pub.dev
- Camera, GPS, file picker, share, local notifications, push notifications, biometrics, in-app purchase, maps, web view, sensors, battery, connectivity, device info, etc.

**haskell-mobile** provides:
- **Permissions**: Request/check for Location, Bluetooth, Camera, Microphone, Contacts, Storage
- **Lifecycle events**: Create, Start, Resume, Pause, Stop, Destroy, LowMemory
- **Locale detection**: `getSystemLocale` via JNI (Android) / system API (iOS)
- **Platform logging**: logcat (Android), os_log (iOS), stderr (desktop)
- **Error handling**: `onError` callback for Haskell exceptions

All platform integration goes through the C bridge (`UIBridge.h`, `PermissionBridge.h`). Adding new platform features requires modifying the C bridge, the Kotlin/Swift bridge, and the Haskell FFI exports.

**Gap**: No camera capture, no GPS/location data, no file picker, no notifications, no network info, no sensors, no maps, no web view, no biometrics. The bridge pattern works but each new feature requires three-layer implementation.

---

### 12. Accessibility

**Flutter** supports:
- `Semantics` widget with 40+ properties (label, hint, value, role, actions, live region, etc.)
- `SemanticsProperties` for custom semantic annotations
- `MergeSemantics` / `ExcludeSemantics` for tree control
- `SemanticsService.announce()` for screen reader announcements
- Built-in platform integration: TalkBack (Android), VoiceOver (iOS)
- `debugDumpSemanticsTree()` for inspection
- Accessibility guidelines checking (large fonts, sufficient contrast)
- Traversal ordering

**haskell-mobile** has no explicit accessibility support. Native widgets (Button, TextInput) inherit platform defaults (the button label will be read by TalkBack/VoiceOver), but there are no semantic annotations, no custom labels, no role overrides, no live region support.

**Gap**: No semantic annotations, no custom accessibility labels, no traversal control, no screen reader announcements.

---

### 13. Internationalization

**Flutter** supports:
- `intl` package with ICU message syntax
- ARB (Application Resource Bundle) files
- Plural forms, gender, select
- Date formatting (`DateFormat`)
- Number formatting (`NumberFormat`)
- Currency formatting
- Bidirectional text
- `Localizations` widget for inherited locale
- Code generation via `intl_utils` or `gen-l10n`
- 78+ locales supported out of the box for Material widgets

**haskell-mobile** supports:
- `I18n` module with `translate :: Map Locale (Map Key Text) -> Locale -> Key -> Either TranslateFailure Text`
- Fallback chain: exact locale -> language-only -> error
- `Locale` type with ISO 639-1 language enum (70+ languages) + optional region
- BCP-47 tag parsing (`parseLocale`)
- System locale detection (`getSystemLocale`)

**Gap**: No plural/gender forms, no date/number/currency formatting, no bidirectional text support, no ARB files, no code generation. The basic translation lookup works but lacks ICU message syntax.

---

### 14. Testing

**Flutter** supports:
- **Unit tests**: Standard Dart test package
- **Widget tests**: Render widgets in test, find by type/text/key, tap/enter text, pump frames
- **Golden tests**: Pixel-perfect screenshot comparison
- **Integration tests**: `integration_test` package with real device/emulator
- **Flutter Driver**: UI automation
- `WidgetTester` with `pumpWidget`, `tap`, `enterText`, `pumpAndSettle`
- `find.byType`, `find.text`, `find.byKey`
- Mock platform channels

**haskell-mobile** supports:
- Unit tests via Tasty (QuickCheck + HUnit)
- Tests for: FFI dispatch, lifecycle routing, widget rendering (serialization to C bridge calls), callback registration, text input handling, ScrollView rendering, Image widget variants, Styled widget, text alignment, color parsing, locale parsing, i18n translation, permission dispatch, AppContext lifecycle, exception handling
- Demo apps (counter, scrollview, textinput, permission, image) as smoke tests
- Desktop stubs allow `cabal test` without mobile devices

**Gap**: No widget-level rendering tests (cannot render and interact with actual UI), no golden/screenshot tests, no integration tests on device. The existing tests validate the Haskell-side logic and C bridge serialization, which is solid, but cannot test the actual native rendering.

---

### 15. Incremental Rendering

**Flutter**:
- Element tree persists across frames; only dirty elements rebuild
- Layout uses cutoff optimizations (same constraints = skip subtree)
- Repaint boundaries isolate repainting to subtrees
- Retained layer rendering (unchanged layers reuse GPU bitmaps)
- `const` widgets skip rebuild via identity check
- O(n) reconciliation only on changed subtrees

**haskell-mobile**:
- Full clear-and-rebuild on every render
- Callback registry (`IntMap`) is cleared and recreated each render
- Every widget tree is serialized to C bridge calls from scratch
- Platform native side presumably clears and recreates all views

**Gap**: No tree diffing, no incremental updates, no retained rendering. Every UI event triggers a full tree serialization and native view recreation.

---

### 16. Platform Targets

**Flutter**: Android, iOS, web (CanvasKit/HTML), macOS, Windows, Linux -- all from one codebase.

**haskell-mobile**: Android (APK via Kotlin/JNI), iOS (static library linked into Xcode), watchOS (Swift bridge), desktop (GHC executable for testing).

**Gap**: Small. haskell-mobile covers the key mobile targets. No web support, but that is a different problem space. watchOS support is a unique advantage that Flutter lacks (Flutter has no watchOS target).

---

### 17. Hot Reload

**Flutter**: Sub-second hot reload preserving app state. The Dart VM injects updated source code into the running isolate, the framework re-runs `build()` on affected widgets, and the UI updates immediately. Hot restart (full restart without state preservation) is also available.

**haskell-mobile**: No hot reload. Changes require recompilation (which involves cross-compilation via Nix for mobile targets) and redeployment to the device. Development iteration uses the desktop target for faster feedback.

**Gap**: Complete. GHC does not support injecting code into a running process. The desktop build target partially mitigates this for logic iteration but not for UI testing on device.

---

### 18. Custom Painting

**Flutter**: `CustomPainter` provides a `Canvas` API for arbitrary 2D drawing: lines, arcs, paths, text, images, gradients, shadows, blend modes, clip regions. Used for charts, custom shapes, games, signatures. Also supports fragment shaders via `FragmentProgram`.

**haskell-mobile**: No custom painting. All rendering is through the predefined widget types.

**Gap**: Complete. Adding a canvas/paint API would require significant bridge work.

---

### 19. Forms and Validation

**Flutter**: `Form` widget groups `TextFormField` widgets. `TextFormField` has `validator` callback returning error string or null. `Form.validate()` runs all validators. `TextEditingController` for programmatic text access. `InputDecoration` for labels, hints, error text, prefixes, suffixes, icons. `FocusNode` for focus management between fields.

**haskell-mobile**: `TextInput` with controlled value (`tiValue`), change callback (`tiOnChange`), hint text (`tiHint`), and keyboard type. No validation, no error display, no form grouping, no focus control.

**Gap**: No validation framework, no error display on inputs, no form grouping, no focus management.

---

### 20. Networking

**Flutter**: The `http` package provides HTTP client. `dio` adds interceptors, retry, upload progress. `web_socket_channel` for WebSockets. `grpc` for gRPC. All async via Dart futures/streams.

**haskell-mobile**: No networking in the framework. Users bring their own (e.g., `http-client`, `req`, `network`). This is arguably the correct approach -- networking is not a UI framework concern.

**Gap**: N/A. Not a framework responsibility, but Flutter's ecosystem makes it seamless.

---

## Summary: Where haskell-mobile Stands

### What haskell-mobile does well

1. **Type safety** -- The widget tree is an algebraic data type. Invalid widget compositions are compile errors.
2. **Simplicity** -- The entire framework is small enough to understand in a single sitting.
3. **watchOS support** -- Flutter does not target watchOS at all.
4. **Direct FFI** -- No serialization bridge. Haskell compiles to native code and calls C functions directly, similar to Dart's advantage over JavaScript.
5. **Testable without devices** -- Desktop stubs allow full logic testing via `cabal test`.
6. **Correct concurrency** -- Haskell's runtime handles threading correctly; no async bridge latency.

### Highest-impact gaps to close

Ranked by impact on real-world app development:

1. **Incremental rendering** -- Full tree rebuild on every event does not scale. A diffing/patching strategy (even a simple one) would dramatically improve performance with larger UIs.
2. **More widgets** -- Checkbox, switch, slider, dropdown, dialog, and progress indicator would cover most common app UI patterns.
3. **Navigation** -- A screen stack with push/pop is essential for multi-screen apps.
4. **Layout flexibility** -- Flex weights on Row/Column, Stack for overlapping, explicit sizing.
5. **Gesture recognition** -- Swipe, long-press, and drag are expected in mobile UIs.
6. **Animation** -- Even basic implicit animations (fade, slide) would make the framework feel production-ready.
7. **Richer text** -- Font weight, font family, and multi-style text spans.
8. **Accessibility** -- Semantic labels on widgets for screen readers.
