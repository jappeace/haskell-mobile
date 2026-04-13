# Animation Support Design (Issue #66)

## Problem

hatter has no mechanism for time-based UI updates. The rendering model
is fully event-driven: `haskellOnUIEvent` triggers `renderView`, which clears
all nodes and rebuilds the entire widget tree from scratch. There is no frame
timer, no interpolation, and no way to animate widget properties over time.

## What Needs Animating

Widget properties that are numeric and already supported:
- Padding, font size
- Text color, background color (RGBA components)

Widget properties that would need adding first:
- Opacity, position offset, scale, rotation

Image animation comes for free: if we re-render at frame rate, the view function
can swap image sources each frame (e.g. sprite sheet index from an animated counter).

## Two Possible Approaches

### 1. Imperative (no tree diffing required)

Animation state lives in `IORef`s outside the widget tree. User explicitly
starts/stops a frame timer. The view function reads current values each render.

```haskell
-- AnimatedValue is an IORef Double that interpolates over time
val <- readAnimatedValue myAnim  -- e.g. 0.0 → 100.0
pure $ text "Hello" <> setPadding (round val)
```

**Pros**: Works with current clear-and-rebuild model. Simple. Matches existing
IORef-based bridge patterns (Location, Camera).

**Cons**: User must manually start/stop the frame timer. Forgetting to stop
wastes CPU at ~60fps. Animation lifecycle is disconnected from widget lifecycle.

### 2. Declarative (requires tree diffing)

Animation is expressed as a widget combinator in the tree itself:

```haskell
animateProperty "padding" 0 100 EaseInOut 0.3 $ \val ->
  text "Hello" <> setPadding (round val)
```

The framework detects animated widgets during rendering, auto-starts the frame
timer when any exist, and auto-stops when none remain. Animation state persists
across re-renders via tree reconciliation.

**Pros**: Safer — no leaked timers. Nicer API. Animation lifecycle tied to
widget presence.

**Cons**: Requires tree diffing or keyed reconciliation. Without it, every
re-render sees a "new" animated widget and restarts the animation from frame 1
(since the tree is cleared and rebuilt each time). At 60fps this means the
animation never progresses.

## Decision: Tree Diffing First

We chose to implement tree diffing/reconciliation before animation, so that we
can build the declarative approach directly. The imperative primitives (frame
timer bridge, easing functions, AnimatedValue) remain useful as internal
building blocks regardless.

## Tree Diffing Prerequisites

The current rendering pipeline (`renderView` in `Hatter.hs`):
1. Clears the entire node pool (`clearNodes`)
2. Calls the user's view function to build a new `Widget`
3. Walks the `Widget` tree, writing each node into the pool (`addNode`)
4. Platform reads the pool and creates native views

To support animation (and improve performance generally), we need:
1. **Retain previous widget tree** — keep the old `Widget` value across renders
2. **Diff old vs new tree** — identify which nodes changed, were added, or removed
3. **Keyed reconciliation** — match nodes across renders (like React's `key` prop)
   so that animated widgets maintain identity
4. **Incremental updates** — instead of clearing and rebuilding, send only diffs
   to the platform (update/add/remove individual nodes)

This is a significant architectural change that touches the core rendering path,
the node pool protocol, and all platform renderers.

## Frame Timer Bridge (needed by both approaches)

Regardless of imperative vs declarative, we need a platform frame timer:

| Platform | API | Frequency |
|----------|-----|-----------|
| Android | `Choreographer.postFrameCallback()` | vsync (~60fps) |
| iOS | `CADisplayLink` | vsync (~60fps) |
| watchOS | `Timer.scheduledTimer()` | ~30fps |
| Desktop stub | Synchronous fake ticks | 3 ticks at 16ms intervals |

The bridge follows the Location pattern: `IORef (Maybe callback)`, single
global callback, C FFI export `haskellOnAnimationTick(ctx, timestamp)`.

Key difference from other bridges: the tick handler must call `renderView`
after dispatching the callback, because animation ticks need to drive UI
updates. No other push-based bridge (Location, Camera, BLE) triggers re-renders.

## Easing Functions (pure, no prerequisites)

These are pure math, implementable independently:

```haskell
data Easing = Linear | EaseIn | EaseOut | EaseInOut

-- from → to → duration → easing → elapsed → interpolated value
evalTween :: Double -> Double -> Double -> Easing -> Double -> Double
```

Easing curves:
- `Linear`: `t`
- `EaseIn`: `t^2`
- `EaseOut`: `1 - (1-t)^2`
- `EaseInOut`: cubic Bezier or smoothstep `3t^2 - 2t^3`

## Implementation Order

1. **Tree diffing / reconciliation** (separate issue/PR)
2. **Frame timer bridge** (Animation bridge PR)
3. **Easing + AnimatedValue** (same PR as frame timer)
4. **Declarative animation combinators** (uses all of the above)

## Files Reference

Key files for understanding the current rendering pipeline:
- `src/Hatter.hs` — `renderView`, `haskellOnUIEvent`, FFI exports
- `src/Hatter/Widget.hs` — `Widget` type, node building
- `include/Hatter.h` — node pool, `MAX_NODES`, native protocol
- `src/Hatter/Location.hs` — IORef callback pattern to follow for timer bridge
- `cbits/location_bridge.c` — desktop stub pattern for timer bridge
