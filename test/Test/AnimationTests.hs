{-# LANGUAGE ImportQualifiedPost #-}
-- | Tests for the animation engine: easing, interpolation,
-- tween registration, and the Animated widget diff behaviour.
module Test.AnimationTests (animationTests) where

import Data.IORef (readIORef, writeIORef)
import Data.Int (Int32)
import Data.IntMap.Strict qualified as IntMap
import Foreign.Ptr (nullPtr)
import Test.Tasty
import Test.Tasty.HUnit

import HaskellMobile
  ( AnimatedConfig(..)
  , Easing(..)
  , newActionState
  )
import HaskellMobile.Animation
  ( ActiveTween(..)
  , AnimationState(..)
  , applyEasing
  , dispatchAnimationFrame
  , interpolateDouble
  , newAnimationState
  , registerTween
  )
import HaskellMobile.Render (RenderState(..), RenderedNode(..), newRenderState, renderWidget)
import HaskellMobile.Widget
  ( Color(..)
  , Widget(..)
  , WidgetStyle(..)
  , TextConfig(..)
  , defaultStyle
  , interpolateColor
  , lerpWord8
  )

animationTests :: TestTree
animationTests = testGroup "Animation"
  [ easingTests
  , interpolationTests
  , colorInterpolationTests
  , tweenRegistryTests
  , animatedWidgetRenderTests
  ]

-- ---------------------------------------------------------------------------
-- Easing
-- ---------------------------------------------------------------------------

easingTests :: TestTree
easingTests = testGroup "Easing"
  [ testCase "Linear at 0 and 1" $ do
      applyEasing Linear 0.0 @?= 0.0
      applyEasing Linear 1.0 @?= 1.0
  , testCase "Linear midpoint" $
      applyEasing Linear 0.5 @?= 0.5
  , testCase "EaseIn at boundaries" $ do
      applyEasing EaseIn 0.0 @?= 0.0
      applyEasing EaseIn 1.0 @?= 1.0
  , testCase "EaseIn slower at 0.25" $ do
      let easeInVal = applyEasing EaseIn 0.25
          linearVal = applyEasing Linear 0.25
      assertBool "EaseIn at 0.25 should be slower than Linear"
        (easeInVal < linearVal)
  , testCase "EaseOut at boundaries" $ do
      applyEasing EaseOut 0.0 @?= 0.0
      applyEasing EaseOut 1.0 @?= 1.0
  , testCase "EaseOut faster at 0.25" $ do
      let easeOutVal = applyEasing EaseOut 0.25
          linearVal  = applyEasing Linear 0.25
      assertBool "EaseOut at 0.25 should be faster than Linear"
        (easeOutVal > linearVal)
  , testCase "EaseInOut at boundaries" $ do
      applyEasing EaseInOut 0.0 @?= 0.0
      applyEasing EaseInOut 1.0 @?= 1.0
  , testCase "EaseInOut symmetry around midpoint" $ do
      let valAt025 = applyEasing EaseInOut 0.25
          valAt075 = applyEasing EaseInOut 0.75
      -- EaseInOut is symmetric: f(0.25) + f(0.75) ≈ 1.0
      assertBool "EaseInOut symmetric"
        (abs (valAt025 + valAt075 - 1.0) < 0.01)
  ]

-- ---------------------------------------------------------------------------
-- Interpolation
-- ---------------------------------------------------------------------------

interpolationTests :: TestTree
interpolationTests = testGroup "Interpolation"
  [ testCase "interpolateDouble boundaries" $ do
      interpolateDouble 10.0 20.0 0.0 @?= 10.0
      interpolateDouble 10.0 20.0 1.0 @?= 20.0
  , testCase "interpolateDouble midpoint" $
      interpolateDouble 10.0 20.0 0.5 @?= 15.0
  , testCase "interpolateDouble negative range" $
      interpolateDouble (-10.0) 10.0 0.5 @?= 0.0
  , testCase "lerpWord8 boundaries" $ do
      lerpWord8 0 255 0.0 @?= 0
      lerpWord8 0 255 1.0 @?= 255
  , testCase "lerpWord8 midpoint" $
      lerpWord8 0 200 0.5 @?= 100
  ]

-- ---------------------------------------------------------------------------
-- Color interpolation
-- ---------------------------------------------------------------------------

colorInterpolationTests :: TestTree
colorInterpolationTests = testGroup "Color interpolation"
  [ testCase "Red to blue midpoint" $ do
      let red  = Color 255 0 0 255
          blue = Color 0 0 255 255
          mid  = interpolateColor red blue 0.5
      colorRed mid   @?= 128
      colorGreen mid @?= 0
      colorBlue mid  @?= 128
      colorAlpha mid @?= 255
  , testCase "Boundaries" $ do
      let from = Color 100 50 200 128
          to   = Color 200 100 50 255
      interpolateColor from to 0.0 @?= from
      interpolateColor from to 1.0 @?= to
  ]

-- ---------------------------------------------------------------------------
-- Tween registry
-- ---------------------------------------------------------------------------

tweenRegistryTests :: TestTree
tweenRegistryTests = testGroup "Tween registry"
  [ testCase "Register and dispatch tween" $ do
      animState <- newAnimationState
      -- Prevent the C stub from calling haskellOnAnimationFrame
      -- by pre-setting ansLoopActive so ensureLoopStarted is a no-op.
      writeIORef (ansContextPtr animState) nullPtr
      writeIORef (ansLoopActive animState) True
      let fromWidget = Text TextConfig { tcLabel = "old", tcFontConfig = Nothing }
          toWidget   = Text TextConfig { tcLabel = "new", tcFontConfig = Nothing }
      registerTween animState 42 fromWidget toWidget 500.0 Linear
      tweens <- readIORef (ansTweens animState)
      assertBool "Tween should be registered" (not (IntMap.null tweens))
  , testCase "Completed tween is removed" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      writeIORef (ansLoopActive animState) True
      let fromWidget = Text TextConfig { tcLabel = "a", tcFontConfig = Nothing }
          toWidget   = Text TextConfig { tcLabel = "b", tcFontConfig = Nothing }
          tween = ActiveTween
            { atStartTime  = Just 0.0
            , atFromWidget = fromWidget
            , atToWidget   = toWidget
            , atNodeId     = 1
            , atDuration   = 100.0
            , atEasing     = Linear
            }
      writeIORef (ansTweens animState) (IntMap.singleton 1 tween)
      -- Dispatch at t=200 (past duration) — tween should complete
      dispatchAnimationFrame animState 200.0
      tweens <- readIORef (ansTweens animState)
      assertBool "Tween should be removed after completion" (IntMap.null tweens)
      loopActive <- readIORef (ansLoopActive animState)
      assertBool "Loop should be stopped" (not loopActive)
  ]

-- ---------------------------------------------------------------------------
-- Animated widget rendering
-- ---------------------------------------------------------------------------

animatedWidgetRenderTests :: TestTree
animatedWidgetRenderTests = testGroup "Animated widget rendering"
  [ testCase "First render creates RenderedAnimated" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      actionState <- newActionState
      rs <- newRenderState actionState animState
      let child = Text TextConfig { tcLabel = "hello", tcFontConfig = Nothing }
          widget = Animated (AnimatedConfig 300 EaseOut) child
      renderWidget rs widget
      renderedTree <- readIORef (rsRenderedTree rs)
      case renderedTree of
        Just (RenderedAnimated _ _) -> pure ()
        other -> assertFailure ("Expected RenderedAnimated, got: " ++ show (fmap renderedNodeSummary other))
  , testCase "Same widget reuses node (Eq match)" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      actionState <- newActionState
      rs <- newRenderState actionState animState
      let child = Text TextConfig { tcLabel = "hello", tcFontConfig = Nothing }
          widget = Animated (AnimatedConfig 300 EaseOut) child
      renderWidget rs widget
      Just firstTree <- readIORef (rsRenderedTree rs)
      let firstNodeId = renderedNodeIdSafe firstTree
      -- Render same widget again — should reuse
      renderWidget rs widget
      Just secondTree <- readIORef (rsRenderedTree rs)
      let secondNodeId = renderedNodeIdSafe secondTree
      firstNodeId @?= secondNodeId
  , testCase "Property change keeps same native node" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      writeIORef (ansLoopActive animState) True
      actionState <- newActionState
      rs <- newRenderState actionState animState
      let child1 = Styled (defaultStyle { wsPadding = Just 10 }) (Text TextConfig { tcLabel = "x", tcFontConfig = Nothing })
          child2 = Styled (defaultStyle { wsPadding = Just 50 }) (Text TextConfig { tcLabel = "x", tcFontConfig = Nothing })
          widget1 = Animated (AnimatedConfig 300 EaseOut) child1
          widget2 = Animated (AnimatedConfig 300 EaseOut) child2
      renderWidget rs widget1
      Just firstTree <- readIORef (rsRenderedTree rs)
      let firstNodeId = renderedNodeIdSafe firstTree
      renderWidget rs widget2
      Just secondTree <- readIORef (rsRenderedTree rs)
      let secondNodeId = renderedNodeIdSafe secondTree
      firstNodeId @?= secondNodeId
  , testCase "Different node type destroys and recreates" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      actionState <- newActionState
      rs <- newRenderState actionState animState
      let child1 = Text TextConfig { tcLabel = "text", tcFontConfig = Nothing }
          child2 = Column []
          widget1 = Animated (AnimatedConfig 300 EaseOut) child1
          widget2 = Animated (AnimatedConfig 300 EaseOut) child2
      renderWidget rs widget1
      Just firstTree <- readIORef (rsRenderedTree rs)
      let firstNodeId = renderedNodeIdSafe firstTree
      renderWidget rs widget2
      Just secondTree <- readIORef (rsRenderedTree rs)
      let secondNodeId = renderedNodeIdSafe secondTree
      -- Different node type means different node ID
      assertBool "Node ID should change for different node types"
        (firstNodeId /= secondNodeId)
  ]

-- | Helper: get the native node ID from a RenderedNode, following through
-- Animated and Styled wrappers.
renderedNodeIdSafe :: RenderedNode -> Int32
renderedNodeIdSafe (RenderedLeaf _ nodeId)        = nodeId
renderedNodeIdSafe (RenderedContainer _ nodeId _) = nodeId
renderedNodeIdSafe (RenderedStyled _ _ child)     = renderedNodeIdSafe child
renderedNodeIdSafe (RenderedAnimated _ child)     = renderedNodeIdSafe child

-- | Helper: produce a short string summary of a RenderedNode for error messages.
renderedNodeSummary :: RenderedNode -> String
renderedNodeSummary (RenderedLeaf _ nodeId)        = "RenderedLeaf " ++ show nodeId
renderedNodeSummary (RenderedContainer _ nodeId _) = "RenderedContainer " ++ show nodeId
renderedNodeSummary (RenderedStyled _ _ child)     = "RenderedStyled -> " ++ renderedNodeSummary child
renderedNodeSummary (RenderedAnimated _ child)     = "RenderedAnimated -> " ++ renderedNodeSummary child
