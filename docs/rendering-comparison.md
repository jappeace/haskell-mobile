# How React Native and Flutter Do Rendering

A technical comparison of the two dominant cross-platform mobile frameworks, written from the perspective of hatter's architecture.

---

## Executive Summary

React Native and Flutter take fundamentally different approaches to mobile rendering:

- **React Native** renders through the platform's native UI toolkit. It runs JavaScript that produces a virtual component tree, diffs it, and sends mutation instructions to iOS UIKit / Android Views. The platform does the actual drawing.
- **Flutter** owns the entire rendering surface. It runs Dart code that produces a render object tree, lays it out, paints it onto a Canvas, and submits GPU commands directly via Impeller (Metal/Vulkan). The platform provides only a blank surface.

Both use a declarative widget model with tree reconciliation, but diverge completely at the rendering layer.

| Concern | React Native | Flutter |
|---|---|---|
| Language | JavaScript (Hermes VM) | Dart (AOT-compiled to native) |
| UI toolkit | Platform-native (UIKit, Android Views) | Custom (Impeller/Skia drawing engine) |
| Layout engine | Yoga (C++ flexbox) | Built-in constraint propagation |
| Tree diffing | O(n) heuristic (type + key) | O(n) linear child-list |
| JS-native bridge | JSI (direct C++ host objects) | None needed (Dart compiles to native) |
| Thread model | 3 threads (JS, Shadow, UI) | 4 task runners (merging to 2) |

---

## Part 1: React

### 1.1 Architecture Overview

React's rendering pipeline separates **reconciliation** (what changed) from **rendering** (applying changes to a host environment). This separation allows the same reconciler to power both React DOM and React Native.

The pipeline:

1. **Trigger** -- A state change (`setState`, `useState` setter) enqueues an update on the relevant fiber node.
2. **Render phase (reconciliation)** -- React traverses the fiber tree, calls component render functions, produces new React elements, and diffs them against the previous tree. This phase is **interruptible** under concurrent rendering. No host mutations occur.
3. **Commit phase** -- React synchronously applies all computed mutations to the host environment (DOM insertions on web; native view creation on mobile). This phase is **not interruptible**.
4. **Passive effects** -- `useEffect` cleanup and setup run asynchronously after commit.

### 1.2 Virtual DOM and Fiber Architecture

#### Virtual DOM

The virtual DOM is a lightweight, in-memory tree of plain JavaScript objects describing the intended UI:

```javascript
{ type: 'View', props: { style: { flex: 1 }, children: [...] } }
```

On state change, React generates a new element tree, diffs it against the previous one, and computes the minimal set of mutations.

#### Fiber Nodes

Each component instance maps to a **fiber node** -- a mutable JS object containing:

| Field | Purpose |
|---|---|
| `type` | Component function/class or host element tag |
| `stateNode` | Reference to the native view or component instance |
| `child` | First child fiber (linked list, not array) |
| `sibling` | Next sibling fiber |
| `return` | Parent fiber |
| `alternate` | Corresponding node in the other tree (current vs. work-in-progress) |
| `pendingProps` | New props at start of work |
| `memoizedProps` | Props after work completes (bail out if equal to pendingProps) |
| `memoizedState` | Current state; for function components, head of hooks linked list |
| `flags` | Bitmask of side effects (Placement, Update, Deletion) |
| `lanes` | Bitmask of pending priority lanes |

The `child`/`sibling`/`return` pointers form a linked-list tree that React traverses iteratively (no recursion, no stack overflow on deep trees).

#### Double Buffering

React maintains two fiber trees simultaneously:

- **Current tree** -- what is on screen.
- **Work-in-progress (WIP) tree** -- being constructed during the render phase.

Each fiber's `alternate` points to its counterpart. At commit, React swaps the root pointer: WIP becomes current, and the old current is reused as the next WIP tree.

#### The Work Loop

```
function workLoopConcurrent() {
  while (workInProgress !== null && !shouldYield()) {
    performUnitOfWork(workInProgress);
  }
}
```

`performUnitOfWork` calls:

1. **`beginWork(fiber)`** -- top-down: calls the component function, returns child fiber. Bails out early if props and state are unchanged.
2. **`completeWork(fiber)`** -- bottom-up: creates/updates the host node, builds the effect list.

Traversal: descend via `child` (calling `beginWork`), at leaves call `completeWork` and follow `sibling`, when siblings exhausted `completeWork` the parent via `return`.

#### Diffing Algorithm

React achieves O(n) diffing via two heuristics:

1. **Elements of different types produce entirely different trees.** A `<View>` replaced by `<Text>` tears down the old subtree entirely.
2. **`key` props hint at stable identity.** In child lists, keys allow matching elements across renders to detect adds, removes, and moves.

### 1.3 React Native: From JavaScript to Native Views

#### New Architecture (default since React Native 0.76)

Three pillars replace the old asynchronous JSON bridge:

**JSI (JavaScript Interface)** -- A C++ API that exposes native objects directly to JavaScript. No JSON serialization. Synchronous calls when needed. Engine-agnostic (works with Hermes, JSC, V8).

**TurboModules** -- Lazily-loaded native modules backed by JSI with Codegen-generated type-safe C++ interfaces.

**Fabric Renderer** -- New rendering system with a shared C++ core:
- Represents UI as an **immutable C++ shadow tree** (structural sharing for unchanged nodes).
- Supports concurrent rendering (shadow trees can be built on any thread).
- Layout via Yoga runs during the commit phase.

#### Fabric Rendering Pipeline

**Phase 1 -- Render**: React executes component logic on the JS thread, producing React elements. Fabric creates a corresponding C++ shadow tree.

**Phase 2 -- Commit**: Yoga calculates layout on the shadow tree. The new tree is promoted as "next tree to mount."

**Phase 3 -- Mount**: The diff between old and new shadow trees produces mount instructions (create view, update props, delete view, insert/remove child) executed on the **UI main thread**.

#### Component Mapping

| React Native | iOS (UIKit) | Android |
|---|---|---|
| `<View>` | `UIView` | `ViewGroup` |
| `<Text>` | Custom text view | `TextView` |
| `<Image>` | `UIImageView` | `ImageView` |
| `<ScrollView>` | `UIScrollView` | `ScrollView` |
| `<TextInput>` | `UITextField` | `EditText` |

Each component has a native **ComponentDescriptor** (Fabric) that creates, updates, and destroys the native view.

#### Threading Model

| Thread | Role |
|---|---|
| **JavaScript** | Executes Dart code, produces element trees |
| **Shadow/Background** | Yoga layout, shadow tree construction (under Fabric, can run on any thread) |
| **UI/Main** | Mounts native views, handles touch events |

Events flow in reverse: native touch → C++ event → JSI → JavaScript handler.

### 1.4 Yoga Layout Engine

Yoga is a C++20 flexbox engine. Each `yoga::Node` corresponds to a view. Layout via `YGNodeCalculateLayout()` does a multi-pass traversal:

1. **Top-down** -- Distribute space along main axis per `flexGrow`/`flexShrink`. Invoke **measure callbacks** for leaf nodes with intrinsic size (text).
2. **Bottom-up** -- Resolve sizes of wrapping containers.
3. **Top-down** -- Resolve percentages, alignment, absolute positioning.

Yoga minimizes measure callback invocations (expensive for text) and caches layout results when constraints haven't changed.

### 1.5 Priority Scheduling (Lanes)

React uses a 31-bit bitmask system with priority groups:

| Lane | Priority | Use |
|---|---|---|
| `SyncLane` | Highest | Discrete user events (tap, keypress) |
| `InputContinuousLane` | High | Drag, scroll |
| `DefaultLane` | Normal | Standard `setState` |
| `TransitionLane` (x16) | Low | `useTransition`; interruptible |
| `IdleLane` | Lowest | Offscreen work |

The scheduler works in ~5ms chunks, yielding to the browser/platform via `MessageChannel` to keep the UI responsive. Higher-priority updates can interrupt in-progress lower-priority renders.

---

## Part 2: Flutter

### 2.1 Architecture Overview

Flutter is a layered system:

```
  Dart Application Code
  ─────────────────────
  Flutter Framework (Dart)
    Material / Cupertino / Widgets / Rendering
  ─────────────────────
  Flutter Engine (C/C++)
    Impeller/Skia, Dart VM, dart:ui, Text
  ─────────────────────
  Platform Embedder (per-OS native code)
  ─────────────────────
  Operating System
```

The **Framework** (Dart) contains widgets, rendering, animation. The **Engine** (C++) provides the Dart runtime, graphics backend, and text layout. The **Embedder** provides a rendering surface, lifecycle, and input events.

### 2.2 The Three Trees

Flutter maintains three parallel trees:

**Widget Tree** -- Immutable, lightweight configuration objects. Recreated on every rebuild (cheap). Widgets describe UI declaratively. A `Container` with a color internally becomes a `ColoredBox`.

**Element Tree** -- Persistent, mutable runtime representation. Each widget inflates into an `Element` holding the current widget and (for `StatefulWidget`) the `State` object. Elements survive across rebuilds; destroyed only when widget type or key changes. Two categories:
- `ComponentElement` -- hosts other elements, has no `RenderObject`.
- `RenderObjectElement` -- intermediary between widget and `RenderObject`.

**RenderObject Tree** -- Used for layout, painting, hit testing, compositing. Long-lived and mutable. Stores geometry and visual properties. A projection of the element tree: only `RenderObjectWidget`-backed elements contribute a node. Layout and paint walk only this tree.

**`BuildContext`** is the `Element` itself.

### 2.3 Reconciliation

Flutter uses **linear child-list reconciliation** (not tree diffing):

1. Match children from beginning and end of old and new lists by `runtimeType` and `key`.
2. Hash remaining unmatched old children by `key`.
3. Walk remaining new children, querying hash table for matches.
4. Unmatched old children are unmounted.
5. Matched children are updated; unmatched new children create fresh elements.

Optimized for common cases: identical lists, single insertion/removal, key-based reordering.

#### Element Lifecycle

1. **`mount()`** -- Inserted into tree, creates `RenderObject`.
2. **`update(widget)`** -- Parent rebuilds with same-type widget, propagates changes.
3. **`deactivate()`** -- Removed from tree (may be reactivated same frame via `GlobalKey`).
4. **`unmount()`** -- End of frame, resources released.

`GlobalKey` enables tree surgery: a widget moved to a different tree location preserves its `Element`, `State`, and `RenderObject`.

### 2.4 Layout System

Single-pass constraint-based layout:

1. **Constraints go down** -- Parent calls `child.layout(BoxConstraints(...))`.
2. **Sizes go up** -- Child computes its size within constraints and returns.
3. **Parent sets position** -- Via `parentData`.

Each render object visited at most twice (down and up). O(n) worst case.

```dart
class BoxConstraints {
  final double minWidth, maxWidth;
  final double minHeight, maxHeight;
  bool get isTight => minWidth == maxWidth && minHeight == maxHeight;
}
```

#### Layout Cutoff Optimizations

- Not dirty + same constraints → skip entire subtree.
- Tight constraints → child size fully determined, parent skips re-layout even if child internals change.
- `sizedByParent` → size depends only on constraints, more aggressive cutoff.
- `parentUsesSize` → if false, child size changes don't propagate upward.

#### Sliver Protocol

For scrollable content, `RenderSliver` receives viewport-aware `SliverConstraints` (visible space, scroll offset). Returns `SliverGeometry`. Enables:
- Lazy child construction (only visible items).
- Interleaved build and layout (framework can call `build()` during layout for slivers).

### 2.5 Painting and Compositing

After layout, `PipelineOwner.flushPaint()` processes dirty render objects in back-to-front depth order.

Each `paint(PaintingContext, Offset)` call records draw commands onto a `Canvas` via `PictureRecorder`. When a compositing boundary is hit (opacity, clip, repaint boundary), the current recording finalizes into a `PictureLayer` and a new layer is pushed.

#### Layer Tree

Painting produces a tree of `Layer` objects:

| Layer | Purpose |
|---|---|
| `ContainerLayer` | Parent of child layers |
| `OffsetLayer` | Position offset (repaint boundaries use this) |
| `PictureLayer` | Immutable sequence of draw commands |
| `ClipPathLayer` | Clipping |
| `OpacityLayer` | Transparency |
| `TextureLayer` | External textures |
| `PlatformViewLayer` | Native views embedded in Flutter |

#### Retained Rendering

Unchanged layers reuse previously rasterized bitmaps via `SceneBuilder.addRetained()`. Each layer tracks whether it needs re-adding to the scene.

#### Scene Submission

1. Root `ContainerLayer` calls `buildScene()` using `SceneBuilder`.
2. `SceneBuilder.build()` produces an immutable `Scene`.
3. `Scene` is submitted to the engine via `FlutterView.render(scene)`.
4. Engine converts to `LayerTree` → GPU commands → pixels.

### 2.6 Impeller (Graphics Engine)

Impeller replaces Skia as Flutter's GPU rendering backend:

- **No runtime shader compilation** -- All shaders (~50) are hand-authored and compiled offline at engine build time. No shader jank ever.
- **All Pipeline State Objects (PSOs) precompiled and cached.**
- **Hardware Abstraction Layer (HAL)** -- Uniform interface over Metal (iOS/macOS), Vulkan (Android API 29+), OpenGL ES (Android fallback).
- **Entity/Content system** -- Each drawable is an `Entity` with a transform matrix, `Contents` (rendering implementation), blend mode, and clip depth. Geometry and shading are cleanly separated.
- **Tessellation** -- Vector paths broken into triangles for GPU rendering via geometry classes with `GetPositionBuffer()`.

Status (Flutter 3.27+):
- iOS: Impeller only (Skia removed).
- Android: Impeller default on API 29+ (Vulkan), OpenGL ES fallback.
- Web: Not Impeller; uses CanvasKit/SkWasm (Skia-based).

Impeller still uses Skia's `SkParagraph` for text layout and Skia's image codecs for decompression.

### 2.7 Platform Embedding

Flutter owns the **entire rendering surface**. The platform provides only a blank canvas:

**Android**: `FlutterActivity` hosts a `FlutterView` (a `FrameLayout` wrapping either `FlutterSurfaceView` or `FlutterTextureView`). The engine draws directly to the `Surface`.

**iOS**: `FlutterViewController` attaches to a `FlutterEngine`. Rendering via Metal to `CAMetalLayer`.

**Platform Views** (native widgets inside Flutter): Hybrid composition copies native view textures into Flutter's compositing pipeline. Hit testing and gestures are bridged between coordinate systems.

### 2.8 Update Cycle (Frame Pipeline)

When `setState()` is called:

1. Element marked dirty, `scheduleFrame()` called.
2. Engine requests vsync from platform.
3. On vsync:

| Phase | What happens |
|---|---|
| **Animation** | Tickers/AnimationControllers update values |
| **Build** | Dirty elements call `build()`, reconcile children |
| **Layout** | `flushLayout()` -- constraints down, sizes up |
| **Compositing bits** | `flushCompositingBits()` -- update layer requirements |
| **Paint** | `flushPaint()` -- record draw commands into layer tree |
| **Composite** | `compositeFrame()` -- build Scene, submit to engine |
| **Semantics** | `flushSemantics()` -- update accessibility tree |

Target: 60 or 120 fps (16.6ms or 8.3ms frame budget).

### 2.9 Dart Runtime

**AOT compilation** -- Release builds compile Dart to native ARM/x64 machine code. No JIT overhead, no serialization bridge.

**Single-threaded event loop** -- Cooperative scheduling within each isolate. Frame callbacks run synchronously. If a phase exceeds the frame budget, jank occurs.

**Isolates** -- For CPU-bound work (>100ms), spawn an isolate (separate memory, message passing). No shared-memory concurrency bugs.

**No serialization bridge** -- Dart code communicates with the C++ engine via `dart:ui` directly (compiled to native). Platform channels use serialization but only for platform API access, not rendering.

### 2.10 Threading Model

Historically four task runners:

| Runner | Role |
|---|---|
| **Platform** | Main OS thread, lifecycle, plugin API calls |
| **UI** | Dart execution, build/layout/paint |
| **Raster** | GPU command submission |
| **IO** | Image decompression, texture prep |

As of Flutter 3.29+, **UI and Platform threads are merged** on iOS and Android. Dart code runs directly on the native platform thread. The raster thread remains separate.

---

## Part 3: Comparison and Lessons for hatter

### 3.1 Rendering Strategy

| | React Native | Flutter | hatter |
|---|---|---|---|
| **Strategy** | Delegate to platform | Own the surface | Delegate to platform |
| **Native look** | Automatic (uses real native widgets) | Must be reimplemented (Material/Cupertino) | Automatic (native widgets) |
| **Consistency** | Varies by platform version | Pixel-identical everywhere | Varies by platform |
| **Drawing custom UI** | Difficult (need native modules) | Natural (Canvas API) | Not yet supported |

hatter follows the React Native strategy: send widget descriptions across a language boundary and let the platform render them. This gives native look-and-feel for free but introduces a communication boundary.

### 3.2 Language Boundary

| | React Native | Flutter | hatter |
|---|---|---|---|
| **Bridge** | JSI (C++ host objects, sync capable) | None (Dart compiles to native) | FFI (`foreign export ccall`) |
| **Serialization** | Eliminated with JSI | None | C structs / manual marshaling |
| **Latency** | Low (direct C++ calls) | Zero | Low (direct function calls) |

Flutter's biggest architectural advantage is that Dart compiles to native code and shares the process with the engine. There is no bridge at all for rendering.

React Native's JSI eliminates the old serialization bottleneck but still crosses a language boundary (JS VM → C++).

hatter uses direct FFI exports, which is conceptually similar to JSI but lower-level. The main pain point is marshaling complex data structures across the boundary.

### 3.3 Layout

| | React Native | Flutter |
|---|---|---|
| **Engine** | Yoga (C++ flexbox subset) | Built-in constraint propagation |
| **Model** | CSS flexbox properties | BoxConstraints (min/max width/height) |
| **Complexity** | Multi-pass (up to 3+ passes) | Single-pass with cutoffs |
| **Custom protocols** | No | Yes (RenderSliver for scrolling) |

Flutter's layout is simpler (single-pass, O(n)) but less familiar to web developers. Yoga implements a more complex multi-pass algorithm to match CSS flexbox semantics.

For hatter, layout is currently handled by the platform (iOS Auto Layout, Android LayoutParams). If hatter ever needs its own layout engine, Flutter's constraint propagation model is simpler to implement than full flexbox.

### 3.4 Tree Reconciliation

Both use O(n) algorithms with similar structure:

| | React | Flutter |
|---|---|---|
| **Identity** | `type` + `key` | `runtimeType` + `key` |
| **Children** | Positional comparison + key map | Match ends, then key hash table |
| **Unchanged** | Skip subtree (memoizedProps === pendingProps) | Skip subtree (identical widget reference) |
| **State** | Preserved when type+key match | Preserved when runtimeType+key match |

The algorithms are nearly identical in spirit. Both prioritize the common case (lists that barely change) and use keys for reordering.

### 3.5 What This Means for hatter

**React Native's model is closer to what hatter does**: both describe a native widget tree from a non-native language and send updates across a boundary. Key lessons:

1. **Immutable shadow trees with structural sharing** (Fabric) are the right model for cross-boundary rendering. hatter's widget descriptions should be diffable with minimal allocation.

2. **Layout should stay on the native side** unless there's a strong reason to move it. Both React Native and hatter benefit from Yoga/platform layout because it avoids reimplementing text measurement and platform conventions.

3. **Synchronous communication matters**. React Native's move from async bridge to synchronous JSI was their biggest architectural improvement. hatter already has synchronous FFI, which is an advantage.

4. **The Flutter model (own the surface) eliminates the bridge problem entirely** but requires reimplementing all platform UI. This is a massive engineering investment that only makes sense with a large team.

5. **AOT compilation eliminates the serialization bridge entirely**. Haskell's compiled-to-native story via GHC is analogous to Dart's AOT compilation -- both produce native machine code that can call C functions directly. This is a structural advantage over JavaScript-based frameworks.

---

## References

### React
- [React Official: Render and Commit](https://react.dev/learn/render-and-commit)
- [React Legacy: Reconciliation](https://legacy.reactjs.org/docs/reconciliation.html)
- [React Native Architecture](https://reactnative.dev/architecture/landing-page)
- [React Native: Fabric Renderer](https://reactnative.dev/architecture/fabric-renderer)
- [React Native: Render Pipeline](https://reactnative.dev/architecture/render-pipeline)
- [React Native: Threading Model](https://reactnative.dev/architecture/threading-model)
- [GitHub: acdlite/react-fiber-architecture](https://github.com/acdlite/react-fiber-architecture)
- [AG Grid: Inside Fiber Reconciliation](https://blog.ag-grid.com/inside-fiber-an-in-depth-overview-of-the-new-reconciliation-algorithm-in-react/)
- [jser.dev: What are Lanes in React Source Code?](https://jser.dev/react/2022/03/26/lanes-in-react/)
- [GitHub: facebook/yoga](https://github.com/facebook/yoga)
- [Yoga Official](https://www.yogalayout.dev/)
- [Meta Engineering: Yoga](https://engineering.fb.com/2016/12/07/android/yoga-a-cross-platform-layout-engine/)

### Flutter
- [Flutter: Inside Flutter](https://docs.flutter.dev/resources/inside-flutter)
- [Flutter: Architectural Overview](https://docs.flutter.dev/resources/architectural-overview)
- [Flutter: Impeller Rendering Engine](https://docs.flutter.dev/perf/impeller)
- [Flutter Engine Architecture](https://github.com/flutter/flutter/blob/main/docs/about/The-Engine-architecture.md)
- [Impeller README (flutter/engine)](https://github.com/flutter/engine/blob/main/impeller/README.md)
- [DeepWiki: Flutter Engine Architecture](https://deepwiki.com/flutter/flutter/4-engine-architecture)
- [Flutter: Understanding Constraints](https://docs.flutter.dev/ui/layout/constraints)
- [PipelineOwner API](https://api.flutter.dev/flutter/rendering/PipelineOwner-class.html)
- [RenderBox API](https://api.flutter.dev/flutter/rendering/RenderBox-class.html)
- [Dart Concurrency](https://dart.dev/language/concurrency)
- [Flutter Isolates](https://docs.flutter.dev/perf/isolates)
- [Thread Merge (GitHub issue)](https://github.com/flutter/flutter/issues/150525)
