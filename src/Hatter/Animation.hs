{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ImportQualifiedPost #-}
-- | Core animation engine for the @Animated@ widget wrapper.
--
-- Manages a registry of active tweens keyed by native node ID.
-- When a property change is detected on an 'Animated' child,
-- the render engine registers a tween here.  The platform frame
-- loop calls 'dispatchAnimationFrame' each vsync, which iterates
-- tweens, computes keyframe-interpolated progress, applies values
-- to native nodes, and removes completed tweens.
module Hatter.Animation
  ( AnimationState(..)
  , ActiveTween(..)
  , newAnimationState
  , registerTween
  , dispatchAnimationFrame
  , bracketKeyframes
  , interpolateDouble
  , interpolateStyle
  -- Re-exported for tests
  , stopLoop
  )
where

import Data.Fixed (Fixed, E6)
import Data.IORef (IORef, newIORef, readIORef, writeIORef, modifyIORef')
import Data.Int (Int32)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.List (sortBy)
import Data.Ord (comparing)
import Data.Time.Clock (NominalDiffTime)
import Foreign.Ptr (Ptr)
import Hatter.Widget
  ( Keyframe(..)
  , WidgetStyle(..)
  , colorToHex
  , interpolateColor
  , unKeyframeAt
  )
import Hatter.UIBridge qualified as Bridge

-- | A single active tween, animating one native node through keyframes.
data ActiveTween = ActiveTween
  { atStartTime  :: Maybe Double
    -- ^ Timestamp (ms) of the first frame; set lazily on first dispatch.
  , atKeyframes  :: [Keyframe]
    -- ^ Keyframes sorted by 'kfAt'.
  , atNodeId     :: Int32
    -- ^ Native node ID to apply interpolated properties to.
  , atDuration   :: NominalDiffTime
    -- ^ Total duration.
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

-- | Register a tween with keyframes for a native node.
-- If a tween already exists for this node ID, it is replaced.
-- Starts the platform frame loop if not already running.
registerTween :: AnimationState -> Int32 -> [Keyframe] -> NominalDiffTime -> IO ()
registerTween animState nodeId keyframes duration = do
  let sortedKeyframes = sortBy (comparing kfAt) keyframes
      tween = ActiveTween
        { atStartTime  = Nothing
        , atKeyframes  = sortedKeyframes
        , atNodeId     = nodeId
        , atDuration   = duration
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
-- computes keyframe-interpolated progress, applies values, and
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
      durationMs = realToFrac (atDuration updatedTween) * 1000.0 :: Double
      rawProgress = if durationMs <= 0
                    then 1.0
                    else min 1.0 (elapsed / durationMs)
  interpolateKeyframeAndApply (atNodeId updatedTween)
                              (atKeyframes updatedTween)
                              rawProgress
  if rawProgress >= 1.0
    then pure Nothing
    else pure (Just updatedTween)

-- | Find the two bracketing keyframes for a given progress value and
-- compute the local segment progress between them.
--
-- Returns @(fromStyle, toStyle, segmentProgress)@.
bracketKeyframes :: [Keyframe] -> Double -> (WidgetStyle, WidgetStyle, Double)
bracketKeyframes [] _progress = (defaultStyleEmpty, defaultStyleEmpty, 0.0)
bracketKeyframes [single] _progress = (kfStyle single, kfStyle single, 0.0)
bracketKeyframes sortedKeyframes progress =
  let progressFixed = realToFrac progress :: Fixed E6
      (firstKf : _) = sortedKeyframes
      lastKf = case reverse sortedKeyframes of
        (x:_) -> x
        []    -> firstKf  -- unreachable: sortedKeyframes is non-empty
  in if progressFixed <= unKeyframeAt (kfAt firstKf)
     then (kfStyle firstKf, kfStyle firstKf, 0.0)
     else if progressFixed >= unKeyframeAt (kfAt lastKf)
     then (kfStyle lastKf, kfStyle lastKf, 0.0)
     else findBracket sortedKeyframes progressFixed
  where
    -- | Find the adjacent keyframe pair that brackets the progress.
    findBracket :: [Keyframe] -> Fixed E6 -> (WidgetStyle, WidgetStyle, Double)
    findBracket (fromKf : toKf : rest) progressVal
      | progressVal < unKeyframeAt (kfAt toKf) =
          let fromAt = realToFrac (unKeyframeAt (kfAt fromKf)) :: Double
              toAt   = realToFrac (unKeyframeAt (kfAt toKf)) :: Double
              segProgress = if toAt == fromAt
                            then 0.0
                            else (realToFrac progressVal - fromAt) / (toAt - fromAt)
          in (kfStyle fromKf, kfStyle toKf, segProgress)
      | otherwise = findBracket (toKf : rest) progressVal
    findBracket [singleKf] _progressVal = (kfStyle singleKf, kfStyle singleKf, 0.0)
    findBracket [] _progressVal = (defaultStyleEmpty, defaultStyleEmpty, 0.0)

-- | Empty style used as fallback for empty keyframe lists.
defaultStyleEmpty :: WidgetStyle
defaultStyleEmpty = WidgetStyle
  { wsPadding          = Nothing
  , wsTextAlign        = Nothing
  , wsTextColor        = Nothing
  , wsBackgroundColor  = Nothing
  , wsTranslateX       = Nothing
  , wsTranslateY       = Nothing
  , wsTouchPassthrough = Nothing
  }

-- | Linearly interpolate between two 'Double' values.
interpolateDouble :: Double -> Double -> Double -> Double
interpolateDouble from to progress = from + (to - from) * progress

-- | Interpolate keyframes and apply the result to the native node.
interpolateKeyframeAndApply :: Int32 -> [Keyframe] -> Double -> IO ()
interpolateKeyframeAndApply nodeId keyframes progress = do
  let (fromStyle, toStyle, segmentProgress) = bracketKeyframes keyframes progress
  interpolateStyle nodeId fromStyle toStyle segmentProgress

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
  -- TranslateX
  case (wsTranslateX fromStyle, wsTranslateX toStyle) of
    (Just fromTx, Just toTx) ->
      Bridge.setNumProp nodeId Bridge.PropTranslateX
        (interpolateDouble fromTx toTx progress)
    (Nothing, Just toTx) ->
      Bridge.setNumProp nodeId Bridge.PropTranslateX toTx
    (Just _fromTx, Nothing) -> pure ()
    (Nothing, Nothing) -> pure ()
  -- TranslateY
  case (wsTranslateY fromStyle, wsTranslateY toStyle) of
    (Just fromTy, Just toTy) ->
      Bridge.setNumProp nodeId Bridge.PropTranslateY
        (interpolateDouble fromTy toTy progress)
    (Nothing, Just toTy) ->
      Bridge.setNumProp nodeId Bridge.PropTranslateY toTy
    (Just _fromTy, Nothing) -> pure ()
    (Nothing, Nothing) -> pure ()
  -- TouchPassthrough (boolean — snaps to target, no interpolation)
  case (wsTouchPassthrough fromStyle, wsTouchPassthrough toStyle) of
    (_, Just enabled) ->
      Bridge.setNumProp nodeId Bridge.PropTouchPassthrough
        (if enabled then 1.0 else 0.0)
    (Just _fromEnabled, Nothing) -> pure ()
    (Nothing, Nothing) -> pure ()

-- | FFI imports for the C animation bridge.
foreign import ccall "animation_start_loop" c_animationStartLoop :: Ptr () -> IO ()
foreign import ccall "animation_stop_loop"  c_animationStopLoop  :: IO ()
