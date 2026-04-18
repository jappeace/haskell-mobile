{-# LANGUAGE ImportQualifiedPost #-}
-- | Tests for the animation engine: keyframes, interpolation,
-- tween registration, and the Animated widget diff behaviour.
module Test.AnimationTests (animationTests) where

import Data.Fixed (Fixed, E6)
import Data.IORef (readIORef, writeIORef)
import Data.Int (Int32)
import Data.IntMap.Strict qualified as IntMap
import Foreign.Ptr (nullPtr)
import Test.Tasty
import Test.Tasty.HUnit

import Hatter
  ( AnimatedConfig(..)
  , Keyframe(..)
  , KeyframeAt
  , mkKeyframeAt
  , unKeyframeAt
  , newActionState
  )
import Hatter.Animation
  ( ActiveTween(..)
  , AnimationState(..)
  , bracketKeyframes
  , dispatchAnimationFrame
  , interpolateDouble
  , interpolateStyle
  , newAnimationState
  , registerTween
  )
import Hatter.Render (RenderState(..), RenderedNode(..), newRenderState, renderWidget)
import Hatter.Widget
  ( Color(..)
  , LayoutSettings(..)
  , Widget(..)
  , WidgetStyle(..)
  , TextConfig(..)
  , column
  , defaultStyle
  , interpolateColor
  , item
  , lerpWord8
  , normalizeAnimated
  )

animationTests :: TestTree
animationTests = testGroup "Animation"
  [ keyframeAtTests
  , interpolationTests
  , colorInterpolationTests
  , keyframeBracketingTests
  , tweenRegistryTests
  , animatedWidgetRenderTests
  , normalizeAnimatedTests
  , translateAnimationTests
  , firstRenderAnimationTests
  ]

-- | Unsafely create a KeyframeAt for test convenience.
unsafeKfAt :: Rational -> KeyframeAt
unsafeKfAt value = case mkKeyframeAt (fromRational value) of
  Just kfAt -> kfAt
  Nothing   -> error ("Invalid keyframe position: " ++ show value)

-- | Make a simple 2-keyframe AnimatedConfig for tests.
twoKeyframeConfig :: Double -> WidgetStyle -> WidgetStyle -> AnimatedConfig
twoKeyframeConfig durationSec fromStyle toStyle = AnimatedConfig
  { anDuration  = realToFrac durationSec
  , anKeyframes =
      [ Keyframe (unsafeKfAt 0) fromStyle
      , Keyframe (unsafeKfAt 1) toStyle
      ]
  }

-- ---------------------------------------------------------------------------
-- KeyframeAt validation
-- ---------------------------------------------------------------------------

keyframeAtTests :: TestTree
keyframeAtTests = testGroup "KeyframeAt"
  [ testCase "Valid values accepted" $ do
      assertBool "0.0 is valid" (mkKeyframeAt 0 /= Nothing)
      assertBool "0.5 is valid" (mkKeyframeAt 0.5 /= Nothing)
      assertBool "1.0 is valid" (mkKeyframeAt 1 /= Nothing)
  , testCase "Invalid values rejected" $ do
      mkKeyframeAt (-0.1) @?= Nothing
      mkKeyframeAt 1.1 @?= Nothing
      mkKeyframeAt 2.0 @?= Nothing
  , testCase "Boundary values" $ do
      assertBool "0.0 accepted" (mkKeyframeAt 0 /= Nothing)
      assertBool "1.0 accepted" (mkKeyframeAt 1 /= Nothing)
  , testCase "unKeyframeAt round-trips" $ do
      let Just kf = mkKeyframeAt 0.5
      unKeyframeAt kf @?= (0.5 :: Fixed E6)
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
-- Keyframe bracketing
-- ---------------------------------------------------------------------------

keyframeBracketingTests :: TestTree
keyframeBracketingTests = testGroup "Keyframe bracketing"
  [ testCase "2-point bracket at start" $ do
      let kfs = [ Keyframe (unsafeKfAt 0) (defaultStyle { wsPadding = Just 0 })
                , Keyframe (unsafeKfAt 1) (defaultStyle { wsPadding = Just 100 })
                ]
          (fromStyle, _toStyle, segProgress) = bracketKeyframes kfs 0.0
      wsPadding fromStyle @?= Just 0
      assertBool "segProgress at start is 0" (segProgress == 0.0)
  , testCase "2-point bracket at end" $ do
      let kfs = [ Keyframe (unsafeKfAt 0) (defaultStyle { wsPadding = Just 0 })
                , Keyframe (unsafeKfAt 1) (defaultStyle { wsPadding = Just 100 })
                ]
          (fromStyle, _toStyle, segProgress) = bracketKeyframes kfs 1.0
      wsPadding fromStyle @?= Just 100
      assertBool "segProgress at end is 0 (clamped)" (segProgress == 0.0)
  , testCase "2-point bracket at midpoint" $ do
      let kfs = [ Keyframe (unsafeKfAt 0) (defaultStyle { wsPadding = Just 0 })
                , Keyframe (unsafeKfAt 1) (defaultStyle { wsPadding = Just 100 })
                ]
          (fromStyle, toStyle, segProgress) = bracketKeyframes kfs 0.5
      wsPadding fromStyle @?= Just 0
      wsPadding toStyle @?= Just 100
      assertBool "segProgress at 0.5 is 0.5" (abs (segProgress - 0.5) < 0.001)
  , testCase "3-point bracket in first segment" $ do
      let kfs = [ Keyframe (unsafeKfAt 0) (defaultStyle { wsTranslateX = Just 0 })
                , Keyframe (unsafeKfAt 0.5) (defaultStyle { wsTranslateX = Just 200 })
                , Keyframe (unsafeKfAt 1) (defaultStyle { wsTranslateX = Just 200 })
                ]
          (fromStyle, toStyle, segProgress) = bracketKeyframes kfs 0.25
      wsTranslateX fromStyle @?= Just 0
      wsTranslateX toStyle @?= Just 200
      assertBool "segProgress at 0.25 in [0,0.5] segment is 0.5" (abs (segProgress - 0.5) < 0.001)
  , testCase "3-point bracket in second segment" $ do
      let kfs = [ Keyframe (unsafeKfAt 0) (defaultStyle { wsTranslateY = Just 0 })
                , Keyframe (unsafeKfAt 0.5) (defaultStyle { wsTranslateY = Just 100 })
                , Keyframe (unsafeKfAt 1) (defaultStyle { wsTranslateY = Just 0 })
                ]
          (fromStyle, toStyle, segProgress) = bracketKeyframes kfs 0.75
      wsTranslateY fromStyle @?= Just 100
      wsTranslateY toStyle @?= Just 0
      assertBool "segProgress at 0.75 in [0.5,1.0] segment is 0.5" (abs (segProgress - 0.5) < 0.001)
  , testCase "Progress before first keyframe clamps to first" $ do
      let kfs = [ Keyframe (unsafeKfAt 0.2) (defaultStyle { wsPadding = Just 10 })
                , Keyframe (unsafeKfAt 0.8) (defaultStyle { wsPadding = Just 50 })
                ]
          (fromStyle, _toStyle, segProgress) = bracketKeyframes kfs 0.0
      wsPadding fromStyle @?= Just 10
      segProgress @?= 0.0
  , testCase "Empty keyframes returns default" $ do
      let (fromStyle, _toStyle, segProgress) = bracketKeyframes [] 0.5
      wsPadding fromStyle @?= Nothing
      segProgress @?= 0.0
  ]

-- ---------------------------------------------------------------------------
-- Tween registry
-- ---------------------------------------------------------------------------

tweenRegistryTests :: TestTree
tweenRegistryTests = testGroup "Tween registry"
  [ testCase "Register and dispatch tween" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      writeIORef (ansLoopActive animState) True
      let keyframes =
            [ Keyframe (unsafeKfAt 0) (defaultStyle { wsPadding = Just 0 })
            , Keyframe (unsafeKfAt 1) (defaultStyle { wsPadding = Just 100 })
            ]
      registerTween animState 42 keyframes 0.5
      tweens <- readIORef (ansTweens animState)
      assertBool "Tween should be registered" (not (IntMap.null tweens))
  , testCase "Completed tween is removed" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      writeIORef (ansLoopActive animState) True
      let keyframes =
            [ Keyframe (unsafeKfAt 0) (defaultStyle { wsPadding = Just 0 })
            , Keyframe (unsafeKfAt 1) (defaultStyle { wsPadding = Just 100 })
            ]
          tween = ActiveTween
            { atStartTime  = Just 0.0
            , atKeyframes  = keyframes
            , atNodeId     = 1
            , atDuration   = 0.1  -- 100ms
            }
      writeIORef (ansTweens animState) (IntMap.singleton 1 tween)
      -- Dispatch at t=200 (past 100ms duration) — tween should complete
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
      writeIORef (ansLoopActive animState) True
      actionState <- newActionState
      rs <- newRenderState actionState animState
      let child = Text TextConfig { tcLabel = "hello", tcFontConfig = Nothing }
          config = twoKeyframeConfig 0.3
                     (defaultStyle { wsPadding = Just 0 })
                     (defaultStyle { wsPadding = Just 10 })
          widget = Animated config child
      renderWidget rs widget
      renderedTree <- readIORef (rsRenderedTree rs)
      case renderedTree of
        Just (RenderedAnimated _ _) -> pure ()
        other -> assertFailure ("Expected RenderedAnimated, got: " ++ show (fmap renderedNodeSummary other))
  , testCase "Same widget reuses node (Eq match)" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      writeIORef (ansLoopActive animState) True
      actionState <- newActionState
      rs <- newRenderState actionState animState
      let child = Text TextConfig { tcLabel = "hello", tcFontConfig = Nothing }
          config = twoKeyframeConfig 0.3
                     (defaultStyle { wsPadding = Just 0 })
                     (defaultStyle { wsPadding = Just 10 })
          widget = Animated config child
      renderWidget rs widget
      Just firstTree <- readIORef (rsRenderedTree rs)
      let firstNodeId = renderedNodeIdSafe firstTree
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
      let config1 = twoKeyframeConfig 0.3
                      (defaultStyle { wsPadding = Just 0 })
                      (defaultStyle { wsPadding = Just 10 })
          config2 = twoKeyframeConfig 0.3
                      (defaultStyle { wsPadding = Just 0 })
                      (defaultStyle { wsPadding = Just 50 })
          child1 = Styled (defaultStyle { wsPadding = Just 10 }) (Text TextConfig { tcLabel = "x", tcFontConfig = Nothing })
          child2 = Styled (defaultStyle { wsPadding = Just 50 }) (Text TextConfig { tcLabel = "x", tcFontConfig = Nothing })
          widget1 = Animated config1 child1
          widget2 = Animated config2 child2
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
      writeIORef (ansLoopActive animState) True
      actionState <- newActionState
      rs <- newRenderState actionState animState
      let config = twoKeyframeConfig 0.3
                     (defaultStyle { wsPadding = Just 0 })
                     (defaultStyle { wsPadding = Just 10 })
          child1 = Text TextConfig { tcLabel = "text", tcFontConfig = Nothing }
          child2 = column []
          widget1 = Animated config child1
          widget2 = Animated config child2
      renderWidget rs widget1
      Just firstTree <- readIORef (rsRenderedTree rs)
      let firstNodeId = renderedNodeIdSafe firstTree
      renderWidget rs widget2
      Just secondTree <- readIORef (rsRenderedTree rs)
      let secondNodeId = renderedNodeIdSafe secondTree
      assertBool "Node ID should change for different node types"
        (firstNodeId /= secondNodeId)
  , testCase "Toggle-back registers tween after animation completes" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      writeIORef (ansLoopActive animState) True
      actionState <- newActionState
      rs <- newRenderState actionState animState
      let configA = twoKeyframeConfig 0.5
                      (defaultStyle { wsPadding = Just 0 })
                      (defaultStyle { wsPadding = Just 10 })
          configB = twoKeyframeConfig 0.5
                      (defaultStyle { wsPadding = Just 0 })
                      (defaultStyle { wsPadding = Just 50 })
          styledA = Styled (defaultStyle { wsPadding = Just 10 }) (Text TextConfig { tcLabel = "x", tcFontConfig = Nothing })
          styledB = Styled (defaultStyle { wsPadding = Just 50 }) (Text TextConfig { tcLabel = "x", tcFontConfig = Nothing })
          widgetA = Animated configA styledA
          widgetB = Animated configB styledB

      -- Render 1: initial state
      renderWidget rs widgetA
      tweensAfter1 <- readIORef (ansTweens animState)
      assertBool "Tween registered after first render" (not (IntMap.null tweensAfter1))

      -- Render 2: change
      renderWidget rs widgetB
      tweensAfter2 <- readIORef (ansTweens animState)
      assertBool "Tween registered after change" (not (IntMap.null tweensAfter2))

      -- Complete the animation
      dispatchAnimationFrame animState 0.0
      dispatchAnimationFrame animState 1000.0
      tweensAfterDispatch <- readIORef (ansTweens animState)
      assertBool "Tween completed after dispatch" (IntMap.null tweensAfterDispatch)

      -- Render 3: toggle back — tween MUST be registered again
      writeIORef (ansLoopActive animState) True
      renderWidget rs widgetA
      tweensAfter3 <- readIORef (ansTweens animState)
      assertBool "Tween registered after toggle-back" (not (IntMap.null tweensAfter3))
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

-- ---------------------------------------------------------------------------
-- normalizeAnimated
-- ---------------------------------------------------------------------------

normalizeAnimatedTests :: TestTree
normalizeAnimatedTests = testGroup "normalizeAnimated"
  [ testCase "Distributes over Column children" $ do
      let cfg = twoKeyframeConfig 0.3
                  (defaultStyle { wsPadding = Just 0 })
                  (defaultStyle { wsPadding = Just 10 })
          childA = Text TextConfig { tcLabel = "a", tcFontConfig = Nothing }
          childB = Text TextConfig { tcLabel = "b", tcFontConfig = Nothing }
          result = normalizeAnimated cfg (Column (LayoutSettings [item childA, item childB] False))
      result @?= Column (LayoutSettings [item (Animated cfg childA), item (Animated cfg childB)] False)
  , testCase "Distributes over Row children" $ do
      let cfg = twoKeyframeConfig 0.3
                  (defaultStyle { wsPadding = Just 0 })
                  (defaultStyle { wsPadding = Just 10 })
          childA = Text TextConfig { tcLabel = "a", tcFontConfig = Nothing }
          result = normalizeAnimated cfg (Row (LayoutSettings [item childA] False))
      result @?= Row (LayoutSettings [item (Animated cfg childA)] False)
  , testCase "Distributes over scrollable Column children" $ do
      let cfg = twoKeyframeConfig 0.3
                  (defaultStyle { wsPadding = Just 0 })
                  (defaultStyle { wsPadding = Just 10 })
          childA = Text TextConfig { tcLabel = "a", tcFontConfig = Nothing }
          result = normalizeAnimated cfg (Column (LayoutSettings [item childA] True))
      result @?= Column (LayoutSettings [item (Animated cfg childA)] True)
  , testCase "Inner Animated wins over outer" $ do
      let outerCfg = twoKeyframeConfig 0.5
                       (defaultStyle { wsPadding = Just 0 })
                       (defaultStyle { wsPadding = Just 10 })
          innerCfg = twoKeyframeConfig 0.1
                       (defaultStyle { wsPadding = Just 0 })
                       (defaultStyle { wsPadding = Just 20 })
          leaf = Text TextConfig { tcLabel = "x", tcFontConfig = Nothing }
          result = normalizeAnimated outerCfg (Animated innerCfg leaf)
      result @?= Animated innerCfg leaf
  , testCase "Styled returned unchanged" $ do
      let cfg = twoKeyframeConfig 0.3
                  (defaultStyle { wsPadding = Just 0 })
                  (defaultStyle { wsPadding = Just 10 })
          style = defaultStyle { wsPadding = Just 10 }
          child = Text TextConfig { tcLabel = "a", tcFontConfig = Nothing }
          result = normalizeAnimated cfg (Styled style child)
      result @?= Styled style child
  , testCase "Leaf widget unchanged" $ do
      let cfg = twoKeyframeConfig 0.3
                  (defaultStyle { wsPadding = Just 0 })
                  (defaultStyle { wsPadding = Just 10 })
          leaf = Text TextConfig { tcLabel = "hi", tcFontConfig = Nothing }
          result = normalizeAnimated cfg leaf
      result @?= leaf
  , testCase "Animated Column renders as RenderedContainer with RenderedAnimated children" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      writeIORef (ansLoopActive animState) True
      actionState <- newActionState
      rs <- newRenderState actionState animState
      let cfg = twoKeyframeConfig 0.3
                  (defaultStyle { wsPadding = Just 0 })
                  (defaultStyle { wsPadding = Just 10 })
          childA = Styled (defaultStyle { wsPadding = Just 10 }) $
                     Text TextConfig { tcLabel = "a", tcFontConfig = Nothing }
          childB = Styled (defaultStyle { wsPadding = Just 20 }) $
                     Text TextConfig { tcLabel = "b", tcFontConfig = Nothing }
          widget = Animated cfg (column [childA, childB])
      renderWidget rs widget
      renderedTree <- readIORef (rsRenderedTree rs)
      case renderedTree of
        Just (RenderedContainer (Column _) _ keyedChildren) -> do
          assertEqual "Should have 2 children" 2 (length keyedChildren)
          mapM_ (\(_key, child) -> case child of
            RenderedAnimated _ (RenderedStyled _ _ _) -> pure ()
            other -> assertFailure ("Expected RenderedAnimated(RenderedStyled), got: "
                                     ++ renderedNodeSummary other)
            ) keyedChildren
        other -> assertFailure ("Expected RenderedContainer, got: "
                                 ++ show (fmap renderedNodeSummary other))
  , testCase "Animated Column re-render with changed child diffs correctly" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      writeIORef (ansLoopActive animState) True
      actionState <- newActionState
      rs <- newRenderState actionState animState
      let cfg = twoKeyframeConfig 0.3
                  (defaultStyle { wsPadding = Just 0 })
                  (defaultStyle { wsPadding = Just 10 })
          style1 = defaultStyle { wsPadding = Just 10 }
          style2 = defaultStyle { wsPadding = Just 50 }
          child = Text TextConfig { tcLabel = "a", tcFontConfig = Nothing }
          widget1 = Animated cfg (column [Styled style1 child])
          widget2 = Animated cfg (column [Styled style2 child])
      renderWidget rs widget1
      Just tree1 <- readIORef (rsRenderedTree rs)
      let nodeId1 = renderedNodeIdSafe tree1
      renderWidget rs widget2
      Just tree2 <- readIORef (rsRenderedTree rs)
      let nodeId2 = renderedNodeIdSafe tree2
      nodeId1 @?= nodeId2
  ]

-- ---------------------------------------------------------------------------
-- Translate animation
-- ---------------------------------------------------------------------------

translateAnimationTests :: TestTree
translateAnimationTests = testGroup "Translate animation"
  [ testCase "Animated translate change keeps same native node" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      writeIORef (ansLoopActive animState) True
      actionState <- newActionState
      rs <- newRenderState actionState animState
      let config1 = twoKeyframeConfig 0.3
                      (defaultStyle { wsTranslateX = Just 0, wsTranslateY = Just 0 })
                      (defaultStyle { wsTranslateX = Just 100, wsTranslateY = Just 50 })
          config2 = twoKeyframeConfig 0.3
                      (defaultStyle { wsTranslateX = Just 0, wsTranslateY = Just 0 })
                      (defaultStyle { wsTranslateX = Just 200, wsTranslateY = Just 100 })
          child1 = Styled (defaultStyle { wsTranslateX = Just 0, wsTranslateY = Just 0 })
                     (Text TextConfig { tcLabel = "t", tcFontConfig = Nothing })
          child2 = Styled (defaultStyle { wsTranslateX = Just 100, wsTranslateY = Just 50 })
                     (Text TextConfig { tcLabel = "t", tcFontConfig = Nothing })
          widget1 = Animated config1 child1
          widget2 = Animated config2 child2
      renderWidget rs widget1
      Just firstTree <- readIORef (rsRenderedTree rs)
      let firstNodeId = renderedNodeIdSafe firstTree
      renderWidget rs widget2
      Just secondTree <- readIORef (rsRenderedTree rs)
      let secondNodeId = renderedNodeIdSafe secondTree
      firstNodeId @?= secondNodeId
  , testCase "defaultStyle has no translate offsets" $ do
      wsTranslateX defaultStyle @?= Nothing
      wsTranslateY defaultStyle @?= Nothing
  , testCase "Styled with translate renders without error" $ do
      actionState <- newActionState
      animState <- newAnimationState
      rs <- newRenderState actionState animState
      renderWidget rs $ Styled (defaultStyle { wsTranslateX = Just 10.5, wsTranslateY = Just (-20.0) })
        (Text TextConfig { tcLabel = "offset", tcFontConfig = Nothing })
  ]

-- ---------------------------------------------------------------------------
-- First-render animation
-- ---------------------------------------------------------------------------

firstRenderAnimationTests :: TestTree
firstRenderAnimationTests = testGroup "First-render animation"
  [ testCase "Animated with 2 keyframes registers tween on first render" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      writeIORef (ansLoopActive animState) True
      actionState <- newActionState
      rs <- newRenderState actionState animState
      let config = twoKeyframeConfig 1.2
                     (defaultStyle { wsTranslateX = Just 0, wsTranslateY = Just 0 })
                     (defaultStyle { wsTranslateX = Just 120, wsTranslateY = Just 50 })
          style = defaultStyle { wsTranslateX = Just 120, wsTranslateY = Just 50 }
          child = Text TextConfig { tcLabel = "*", tcFontConfig = Nothing }
          widget = Animated config (Styled style child)
      renderWidget rs widget
      tweens <- readIORef (ansTweens animState)
      assertBool "Tween registered on first render for translate" (not (IntMap.null tweens))
  , testCase "Animated with 1 keyframe has no tween on first render" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      actionState <- newActionState
      rs <- newRenderState actionState animState
      let config = AnimatedConfig
            { anDuration = 0.3
            , anKeyframes = [Keyframe (unsafeKfAt 0) (defaultStyle { wsPadding = Just 10 })]
            }
          widget = Animated config
                     (Text TextConfig { tcLabel = "hello", tcFontConfig = Nothing })
      renderWidget rs widget
      tweens <- readIORef (ansTweens animState)
      assertBool "No tween for single keyframe" (IntMap.null tweens)
  , testCase "Animated with empty keyframes has no tween" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      actionState <- newActionState
      rs <- newRenderState actionState animState
      let config = AnimatedConfig { anDuration = 0.3, anKeyframes = [] }
          widget = Animated config
                     (Text TextConfig { tcLabel = "hello", tcFontConfig = Nothing })
      renderWidget rs widget
      tweens <- readIORef (ansTweens animState)
      assertBool "No tween for empty keyframes" (IntMap.null tweens)
  , testCase "3-keyframe animation registers tween on first render" $ do
      animState <- newAnimationState
      writeIORef (ansContextPtr animState) nullPtr
      writeIORef (ansLoopActive animState) True
      actionState <- newActionState
      rs <- newRenderState actionState animState
      let config = AnimatedConfig
            { anDuration = 2.0
            , anKeyframes =
                [ Keyframe (unsafeKfAt 0) (defaultStyle { wsTranslateX = Just 0, wsTranslateY = Just 0 })
                , Keyframe (unsafeKfAt 0.5) (defaultStyle { wsTranslateX = Just 200, wsTranslateY = Just 100 })
                , Keyframe (unsafeKfAt 1) (defaultStyle { wsTranslateX = Just 200, wsTranslateY = Just 0 })
                ]
            }
          child = Text TextConfig { tcLabel = "*", tcFontConfig = Nothing }
          widget = Animated config (Styled (defaultStyle { wsTranslateX = Just 200, wsTranslateY = Just 0 }) child)
      renderWidget rs widget
      tweens <- readIORef (ansTweens animState)
      assertBool "Tween registered for 3-keyframe animation" (not (IntMap.null tweens))
  ]
