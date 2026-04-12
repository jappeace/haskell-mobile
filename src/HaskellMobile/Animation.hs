{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ImportQualifiedPost #-}
-- | Core animation engine for the @Animated@ widget wrapper.
--
-- Manages a registry of active tweens keyed by native node ID.
-- When a property change is detected on an 'Animated' child,
-- the render engine registers a tween here.  The platform frame
-- loop calls 'dispatchAnimationFrame' each vsync, which iterates
-- tweens, computes eased progress, applies interpolated property
-- values to native nodes, and removes completed tweens.
module HaskellMobile.Animation
  ( AnimationState(..)
  , ActiveTween(..)
  , newAnimationState
  , registerTween
  , dispatchAnimationFrame
  , applyEasing
  , interpolateDouble
  , interpolateAndApply
  -- Re-exported for tests
  , stopLoop
  )
where

import Data.IORef (IORef, newIORef, readIORef, writeIORef, modifyIORef')
import Data.Int (Int32)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Foreign.Ptr (Ptr)
import HaskellMobile.Widget
  ( Easing(..)
  , FontConfig(..)
  , MapViewConfig(..)
  , TextConfig(..)
  , ButtonConfig(..)
  , TextInputConfig(..)
  , Widget(..)
  , WidgetStyle(..)
  , colorToHex
  , interpolateColor
  )
import HaskellMobile.UIBridge qualified as Bridge
import System.IO (hPutStrLn, stderr)

-- | A single active tween, animating one native node from old to new properties.
data ActiveTween = ActiveTween
  { atStartTime  :: Maybe Double
    -- ^ Timestamp (ms) of the first frame; set lazily on first dispatch.
  , atFromWidget :: Widget
    -- ^ The widget we are animating FROM (old property values).
  , atToWidget   :: Widget
    -- ^ The widget we are animating TO (new property values).
  , atNodeId     :: Int32
    -- ^ Native node ID to apply interpolated properties to.
  , atDuration   :: Double
    -- ^ Total duration in milliseconds.
  , atEasing     :: Easing
    -- ^ Easing function.
  }

-- | Mutable state for the animation engine.
data AnimationState = AnimationState
  { ansTweens     :: IORef (IntMap ActiveTween)
    -- ^ Active tweens, keyed by native node ID.
  , ansLoopActive :: IORef Bool
    -- ^ Whether the platform frame loop is currently running.
  , ansContextPtr :: IORef (Ptr ())
    -- ^ Haskell context pointer, written by AppContext initialisation.
  }

-- | Create a fresh 'AnimationState' with no active tweens.
newAnimationState :: IO AnimationState
newAnimationState = do
  tweens     <- newIORef IntMap.empty
  loopActive <- newIORef False
  ctxPtr     <- newIORef (error "AnimationState: context pointer not set")
  pure AnimationState
    { ansTweens     = tweens
    , ansLoopActive = loopActive
    , ansContextPtr = ctxPtr
    }

-- | Register a tween from old widget properties to new widget properties.
-- If a tween already exists for this node ID, it is replaced (the old
-- tween's current target becomes irrelevant).  Starts the platform
-- frame loop if not already running.
registerTween :: AnimationState -> Int32 -> Widget -> Widget -> Double -> Easing -> IO ()
registerTween animState nodeId fromWidget toWidget duration easing = do
  let tween = ActiveTween
        { atStartTime  = Nothing
        , atFromWidget = fromWidget
        , atToWidget   = toWidget
        , atNodeId     = nodeId
        , atDuration   = duration
        , atEasing     = easing
        }
  modifyIORef' (ansTweens animState) (IntMap.insert (fromIntegral nodeId) tween)
  ensureLoopStarted animState

-- | Start the platform animation loop if not already active.
ensureLoopStarted :: AnimationState -> IO ()
ensureLoopStarted animState = do
  active <- readIORef (ansLoopActive animState)
  if active
    then pure ()
    else do
      writeIORef (ansLoopActive animState) True
      ctxPtr <- readIORef (ansContextPtr animState)
      c_animationStartLoop ctxPtr

-- | Stop the platform animation loop.
stopLoop :: AnimationState -> IO ()
stopLoop animState = do
  writeIORef (ansLoopActive animState) False
  c_animationStopLoop

-- | Process one animation frame.  Called by the FFI entry point
-- @haskellOnAnimationFrame@ each vsync.  Iterates all active tweens,
-- computes eased progress, applies interpolated properties, and
-- removes completed tweens.  Stops the loop when no tweens remain.
dispatchAnimationFrame :: AnimationState -> Double -> IO ()
dispatchAnimationFrame animState timestampMs = do
  tweens <- readIORef (ansTweens animState)
  if IntMap.null tweens
    then stopLoop animState
    else do
      -- Process each tween, collecting those that are still active
      remaining <- IntMap.traverseWithKey (processTween timestampMs) tweens
      let activeTweens = IntMap.mapMaybe id remaining
      writeIORef (ansTweens animState) activeTweens
      if IntMap.null activeTweens
        then stopLoop animState
        else pure ()

-- | Process a single tween for the current frame.
-- Returns 'Nothing' if the tween is complete, 'Just tween' if still active.
processTween :: Double -> IntMap.Key -> ActiveTween -> IO (Maybe ActiveTween)
processTween timestampMs _key tween = do
  let startTime = case atStartTime tween of
        Just t  -> t
        Nothing -> timestampMs
      updatedTween = tween { atStartTime = Just startTime }
      elapsed = timestampMs - startTime
      rawProgress = if atDuration updatedTween <= 0
                    then 1.0
                    else min 1.0 (elapsed / atDuration updatedTween)
      easedProgress = applyEasing (atEasing updatedTween) rawProgress
  interpolateAndApply (atNodeId updatedTween) (atFromWidget updatedTween)
                      (atToWidget updatedTween) easedProgress
  if rawProgress >= 1.0
    then pure Nothing
    else pure (Just updatedTween)

-- | Apply easing to a linear progress value (0–1).
applyEasing :: Easing -> Double -> Double
applyEasing Linear    progress = progress
applyEasing EaseIn    progress = progress * progress * progress
applyEasing EaseOut   progress =
  let inverted = 1.0 - progress
  in 1.0 - inverted * inverted * inverted
applyEasing EaseInOut progress =
  if progress < 0.5
    then 4.0 * progress * progress * progress
    else 1.0 - ((-2.0 * progress + 2.0) ** 3) / 2.0

-- | Linearly interpolate between two 'Double' values.
interpolateDouble :: Double -> Double -> Double -> Double
interpolateDouble from to progress = from + (to - from) * progress

-- | Interpolate properties between two widgets and apply them to the
-- native node via bridge calls.  Only animatable properties (numeric
-- and color) are interpolated; others snap to the target instantly.
interpolateAndApply :: Int32 -> Widget -> Widget -> Double -> IO ()
interpolateAndApply nodeId (Styled fromStyle _) (Styled toStyle _) progress =
  interpolateStyle nodeId fromStyle toStyle progress
interpolateAndApply nodeId (MapView fromConfig) (MapView toConfig) progress = do
  Bridge.setNumProp nodeId Bridge.PropMapLat
    (interpolateDouble (mvLatitude fromConfig) (mvLatitude toConfig) progress)
  Bridge.setNumProp nodeId Bridge.PropMapLon
    (interpolateDouble (mvLongitude fromConfig) (mvLongitude toConfig) progress)
  Bridge.setNumProp nodeId Bridge.PropMapZoom
    (interpolateDouble (mvZoom fromConfig) (mvZoom toConfig) progress)
interpolateAndApply nodeId (Text fromConfig) (Text toConfig) progress =
  interpolateFontSize nodeId (tcFontConfig fromConfig) (tcFontConfig toConfig) progress
interpolateAndApply nodeId (Button fromConfig) (Button toConfig) progress =
  interpolateFontSize nodeId (bcFontConfig fromConfig) (bcFontConfig toConfig) progress
interpolateAndApply nodeId (TextInput fromConfig) (TextInput toConfig) progress =
  interpolateFontSize nodeId (tiFontConfig fromConfig) (tiFontConfig toConfig) progress
-- Non-animatable widget types: log warning (should not normally happen)
interpolateAndApply _nodeId _from _to _progress =
  hPutStrLn stderr "interpolateAndApply: non-animatable widget pair"

-- | Interpolate 'WidgetStyle' properties and apply them to a native node.
interpolateStyle :: Int32 -> WidgetStyle -> WidgetStyle -> Double -> IO ()
interpolateStyle nodeId fromStyle toStyle progress = do
  -- Padding
  case (wsPadding fromStyle, wsPadding toStyle) of
    (Just fromPad, Just toPad) ->
      Bridge.setNumProp nodeId Bridge.PropPadding
        (interpolateDouble fromPad toPad progress)
    (Nothing, Just toPad) ->
      Bridge.setNumProp nodeId Bridge.PropPadding toPad
    (Just _fromPad, Nothing) -> pure ()
    (Nothing, Nothing) -> pure ()
  -- Text color
  case (wsTextColor fromStyle, wsTextColor toStyle) of
    (Just fromColor, Just toColor) ->
      Bridge.setStrProp nodeId Bridge.PropColor
        (colorToHex (interpolateColor fromColor toColor progress))
    (Nothing, Just toColor) ->
      Bridge.setStrProp nodeId Bridge.PropColor (colorToHex toColor)
    (Just _fromColor, Nothing) -> pure ()
    (Nothing, Nothing) -> pure ()
  -- Background color
  case (wsBackgroundColor fromStyle, wsBackgroundColor toStyle) of
    (Just fromColor, Just toColor) ->
      Bridge.setStrProp nodeId Bridge.PropBgColor
        (colorToHex (interpolateColor fromColor toColor progress))
    (Nothing, Just toColor) ->
      Bridge.setStrProp nodeId Bridge.PropBgColor (colorToHex toColor)
    (Just _fromColor, Nothing) -> pure ()
    (Nothing, Nothing) -> pure ()

-- | Interpolate font size between two optional 'FontConfig' values.
interpolateFontSize :: Int32 -> Maybe FontConfig -> Maybe FontConfig -> Double -> IO ()
interpolateFontSize nodeId (Just (FontConfig fromSize)) (Just (FontConfig toSize)) progress =
  Bridge.setNumProp nodeId Bridge.PropFontSize
    (interpolateDouble fromSize toSize progress)
interpolateFontSize nodeId Nothing (Just (FontConfig toSize)) _progress =
  Bridge.setNumProp nodeId Bridge.PropFontSize toSize
interpolateFontSize _nodeId (Just _) Nothing _progress = pure ()
interpolateFontSize _nodeId Nothing Nothing _progress = pure ()

-- | FFI imports for the C animation bridge.
foreign import ccall "animation_start_loop" c_animationStartLoop :: Ptr () -> IO ()
foreign import ccall "animation_stop_loop"  c_animationStopLoop  :: IO ()
