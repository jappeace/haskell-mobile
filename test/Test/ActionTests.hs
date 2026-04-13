-- | Tests for Action/OnChange handles, Widget Eq, and incremental rendering.
module Test.ActionTests
  ( actionTests
  , widgetEqTests
  , incrementalRenderTests
  ) where

import Test.Tasty
import Test.Tasty.HUnit

import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Int (Int32)
import Hatter
  ( Action(..)
  , OnChange(..)
  , createAction
  , createOnChange
  , newActionState
  , runActionM
  )
import Hatter.Widget
  ( ButtonConfig(..)
  , TextConfig(..)
  , Widget(..)
  , WidgetStyle(..)
  )
import Hatter.Render
  ( RenderState(..)
  , RenderedNode(..)
  , renderWidget
  , dispatchEvent
  )
import Test.Helpers (withActions)

-- | Tests for Action/OnChange handle equality and creation.
actionTests :: TestTree
actionTests = testGroup "Action"
  [ testCase "createAction produces unique IDs" $ do
      actionState <- newActionState
      (handleA, handleB) <- runActionM actionState $ do
        hA <- createAction (pure ())
        hB <- createAction (pure ())
        pure (hA, hB)
      assertBool "different actions should have different IDs" (handleA /= handleB)

  , testCase "createOnChange produces unique IDs" $ do
      actionState <- newActionState
      (handleA, handleB) <- runActionM actionState $ do
        hA <- createOnChange (\_ -> pure ())
        hB <- createOnChange (\_ -> pure ())
        pure (hA, hB)
      assertBool "different onChange handles should have different IDs" (handleA /= handleB)

  , testCase "Action and OnChange share ID space" $ do
      actionState <- newActionState
      (actionHandle, changeHandle) <- runActionM actionState $ do
        ah <- createAction (pure ())
        ch <- createOnChange (\_ -> pure ())
        pure (ah, ch)
      assertBool "action and onChange should have different IDs"
        (actionId actionHandle /= onChangeId changeHandle)

  , testCase "same Action handle equals itself" $ do
      actionState <- newActionState
      handle <- runActionM actionState $ createAction (pure ())
      handle @?= handle
  ]

-- | Tests for Widget Eq instance (enabled by opaque handles).
widgetEqTests :: TestTree
widgetEqTests = testGroup "WidgetEq"
  [ testCase "same widget with same handle is equal" $ do
      actionState <- newActionState
      handle <- runActionM actionState $ createAction (pure ())
      let widgetA = Button ButtonConfig { bcLabel = "tap", bcAction = handle, bcFontConfig = Nothing }
          widgetB = Button ButtonConfig { bcLabel = "tap", bcAction = handle, bcFontConfig = Nothing }
      widgetA @?= widgetB

  , testCase "same widget with different handles is not equal" $ do
      actionState <- newActionState
      (handleA, handleB) <- runActionM actionState $ do
        hA <- createAction (pure ())
        hB <- createAction (pure ())
        pure (hA, hB)
      let widgetA = Button ButtonConfig { bcLabel = "tap", bcAction = handleA, bcFontConfig = Nothing }
          widgetB = Button ButtonConfig { bcLabel = "tap", bcAction = handleB, bcFontConfig = Nothing }
      assertBool "different handles means different widgets" (widgetA /= widgetB)

  , testCase "Text widgets with same content are equal" $ do
      let widgetA = Text TextConfig { tcLabel = "hello", tcFontConfig = Nothing }
          widgetB = Text TextConfig { tcLabel = "hello", tcFontConfig = Nothing }
      widgetA @?= widgetB

  , testCase "Text widgets with different content are not equal" $ do
      let widgetA = Text TextConfig { tcLabel = "hello", tcFontConfig = Nothing }
          widgetB = Text TextConfig { tcLabel = "world", tcFontConfig = Nothing }
      assertBool "different labels means different widgets" (widgetA /= widgetB)

  , testCase "Column equality is structural" $ do
      let widgetA = Column [Text TextConfig { tcLabel = "a", tcFontConfig = Nothing }]
          widgetB = Column [Text TextConfig { tcLabel = "a", tcFontConfig = Nothing }]
          widgetC = Column [Text TextConfig { tcLabel = "b", tcFontConfig = Nothing }]
      widgetA @?= widgetB
      assertBool "different children means different Column" (widgetA /= widgetC)
  ]

-- ---------------------------------------------------------------------------
-- Incremental rendering tests
-- ---------------------------------------------------------------------------

-- | Helper to extract the rendered node ID from a RenderedNode.
nodeIdOf :: RenderedNode -> Int32
nodeIdOf (RenderedLeaf _ nodeId)         = nodeId
nodeIdOf (RenderedContainer _ nodeId _)  = nodeId
nodeIdOf (RenderedStyled _ _ child)      = nodeIdOf child
nodeIdOf (RenderedAnimated _ child)      = nodeIdOf child

-- | Helper to extract children from a RenderedContainer.
childrenOf :: RenderedNode -> [RenderedNode]
childrenOf (RenderedContainer _ _ children) = children
childrenOf (RenderedLeaf _ _)              = []
childrenOf (RenderedStyled _ _ _)          = []
childrenOf (RenderedAnimated _ _)          = []

incrementalRenderTests :: TestTree
incrementalRenderTests = testGroup "Incremental rendering"
  [ testGroup "Node reuse"
      [ testCase "identical re-render retains same node ID" $ do
          ((), rs) <- withActions (pure ())
          let widget = Text TextConfig { tcLabel = "static", tcFontConfig = Nothing }
          renderWidget rs widget
          tree1 <- readIORef (rsRenderedTree rs)
          let nodeId1 = case tree1 of
                Just node -> nodeIdOf node
                Nothing   -> -1
          renderWidget rs widget
          tree2 <- readIORef (rsRenderedTree rs)
          let nodeId2 = case tree2 of
                Just node -> nodeIdOf node
                Nothing   -> -2
          nodeId1 @?= nodeId2

      , testCase "single child change only changes that child's node ID" $ do
          ((), rs) <- withActions (pure ())
          let widget1 = Column
                [ Text TextConfig { tcLabel = "stable", tcFontConfig = Nothing }
                , Text TextConfig { tcLabel = "will change", tcFontConfig = Nothing }
                ]
          renderWidget rs widget1
          tree1 <- readIORef (rsRenderedTree rs)
          (child0Id1, child1Id1) <- case tree1 of
            Just node -> case childrenOf node of
              [c0, c1] -> pure (nodeIdOf c0, nodeIdOf c1)
              _        -> assertFailure "expected 2 children" >> pure (-1, -1)
            Nothing -> assertFailure "expected rendered tree" >> pure (-1, -1)
          let widget2 = Column
                [ Text TextConfig { tcLabel = "stable", tcFontConfig = Nothing }
                , Text TextConfig { tcLabel = "changed!", tcFontConfig = Nothing }
                ]
          renderWidget rs widget2
          tree2 <- readIORef (rsRenderedTree rs)
          (child0Id2, child1Id2) <- case tree2 of
            Just node -> case childrenOf node of
              [c0, c1] -> pure (nodeIdOf c0, nodeIdOf c1)
              _        -> assertFailure "expected 2 children" >> pure (-1, -1)
            Nothing -> assertFailure "expected rendered tree" >> pure (-1, -1)
          -- First child (unchanged) keeps same node ID
          child0Id1 @?= child0Id2
          -- Second child (changed) gets a different node ID
          assertBool "changed child should get new node ID"
            (child1Id1 /= child1Id2)

      , testCase "callback-only handle change triggers new node" $ do
          ref <- newIORef ("none" :: String)
          ((handle1, handle2), rs) <- withActions $ do
            h1 <- createAction (writeIORef ref "action1")
            h2 <- createAction (writeIORef ref "action2")
            pure (h1, h2)
          -- Render button with handle1
          let widget1 = Button ButtonConfig
                { bcLabel = "same label", bcAction = handle1, bcFontConfig = Nothing }
          renderWidget rs widget1
          tree1 <- readIORef (rsRenderedTree rs)
          let nodeId1 = case tree1 of
                Just node -> nodeIdOf node
                Nothing   -> -1
          -- Render same label but with handle2 (different Eq)
          let widget2 = Button ButtonConfig
                { bcLabel = "same label", bcAction = handle2, bcFontConfig = Nothing }
          renderWidget rs widget2
          tree2 <- readIORef (rsRenderedTree rs)
          let nodeId2 = case tree2 of
                Just node -> nodeIdOf node
                Nothing   -> -2
          -- Different handle means different Widget (Eq), so new node
          assertBool "different handle should produce new node ID"
            (nodeId1 /= nodeId2)
          -- Dispatch handle2 — should fire action2
          dispatchEvent rs (actionId handle2)
          result <- readIORef ref
          result @?= "action2"

      , testCase "same handle reuses node" $ do
          ref <- newIORef ("none" :: String)
          (handle, rs) <- withActions $
            createAction (writeIORef ref "fired")
          -- Render button with handle
          let widget1 = Button ButtonConfig
                { bcLabel = "same label", bcAction = handle, bcFontConfig = Nothing }
          renderWidget rs widget1
          tree1 <- readIORef (rsRenderedTree rs)
          let nodeId1 = case tree1 of
                Just node -> nodeIdOf node
                Nothing   -> -1
          -- Re-render identical widget
          renderWidget rs widget1
          tree2 <- readIORef (rsRenderedTree rs)
          let nodeId2 = case tree2 of
                Just node -> nodeIdOf node
                Nothing   -> -2
          -- Same handle, same label → reused node
          nodeId1 @?= nodeId2
          -- Dispatch still works
          dispatchEvent rs (actionId handle)
          result <- readIORef ref
          result @?= "fired"

      , testCase "adding a child to container" $ do
          ((), rs) <- withActions (pure ())
          let widget1 = Column
                [ Text TextConfig { tcLabel = "first", tcFontConfig = Nothing } ]
          renderWidget rs widget1
          tree1 <- readIORef (rsRenderedTree rs)
          existingChildId <- case tree1 of
            Just node -> case childrenOf node of
              [c0] -> pure (nodeIdOf c0)
              _    -> assertFailure "expected 1 child" >> pure (-1)
            Nothing -> assertFailure "expected rendered tree" >> pure (-1)
          let widget2 = Column
                [ Text TextConfig { tcLabel = "first", tcFontConfig = Nothing }
                , Text TextConfig { tcLabel = "second", tcFontConfig = Nothing }
                ]
          renderWidget rs widget2
          tree2 <- readIORef (rsRenderedTree rs)
          case tree2 of
            Just node -> case childrenOf node of
              [c0, c1] -> do
                -- First child retained
                nodeIdOf c0 @?= existingChildId
                -- Second child is new (different ID)
                assertBool "new child should have different ID"
                  (nodeIdOf c1 /= existingChildId)
              _ -> assertFailure "expected 2 children"
            Nothing -> assertFailure "expected rendered tree"

      , testCase "removing a child from container" $ do
          ((), rs) <- withActions (pure ())
          let widget1 = Column
                [ Text TextConfig { tcLabel = "a", tcFontConfig = Nothing }
                , Text TextConfig { tcLabel = "b", tcFontConfig = Nothing }
                ]
          renderWidget rs widget1
          let widget2 = Column
                [ Text TextConfig { tcLabel = "a", tcFontConfig = Nothing } ]
          renderWidget rs widget2
          tree2 <- readIORef (rsRenderedTree rs)
          let children2 = childrenOf (maybe (error "no tree") id tree2)
          length children2 @?= 1

      , testCase "root type change triggers new root node" $ do
          (handle, rs) <- withActions $
            createAction (pure ())
          let widget1 = Text TextConfig { tcLabel = "text", tcFontConfig = Nothing }
          renderWidget rs widget1
          tree1 <- readIORef (rsRenderedTree rs)
          let nodeId1 = case tree1 of
                Just node -> nodeIdOf node
                Nothing   -> -1
          let widget2 = Button ButtonConfig
                { bcLabel = "button", bcAction = handle, bcFontConfig = Nothing }
          renderWidget rs widget2
          tree2 <- readIORef (rsRenderedTree rs)
          let nodeId2 = case tree2 of
                Just node -> nodeIdOf node
                Nothing   -> -2
          assertBool "different widget type should produce new node ID"
            (nodeId1 /= nodeId2)

      , testCase "styled unchanged keeps same node ID" $ do
          ((), rs) <- withActions (pure ())
          let style = WidgetStyle (Just 10.0) Nothing Nothing Nothing Nothing Nothing
              widget = Styled style (Text TextConfig { tcLabel = "styled", tcFontConfig = Nothing })
          renderWidget rs widget
          tree1 <- readIORef (rsRenderedTree rs)
          let nodeId1 = case tree1 of
                Just node -> nodeIdOf node
                Nothing   -> -1
          renderWidget rs widget
          tree2 <- readIORef (rsRenderedTree rs)
          let nodeId2 = case tree2 of
                Just node -> nodeIdOf node
                Nothing   -> -2
          nodeId1 @?= nodeId2

      , testCase "styled child change updates child" $ do
          ((), rs) <- withActions (pure ())
          let style = WidgetStyle (Just 10.0) Nothing Nothing Nothing Nothing Nothing
              widget1 = Styled style (Text TextConfig { tcLabel = "before", tcFontConfig = Nothing })
          renderWidget rs widget1
          tree1 <- readIORef (rsRenderedTree rs)
          let nodeId1 = case tree1 of
                Just node -> nodeIdOf node
                Nothing   -> -1
          let widget2 = Styled style (Text TextConfig { tcLabel = "after", tcFontConfig = Nothing })
          renderWidget rs widget2
          tree2 <- readIORef (rsRenderedTree rs)
          let nodeId2 = case tree2 of
                Just node -> nodeIdOf node
                Nothing   -> -2
          -- Child changed, so node should be different
          assertBool "changed styled child should get new node"
            (nodeId1 /= nodeId2)
      ]
  ]
