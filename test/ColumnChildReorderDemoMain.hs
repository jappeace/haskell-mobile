{-# LANGUAGE OverloadedStrings #-}
-- | Reproducer: reordering children in a Column container.
--
-- Tests diffContainer's unstable path (remove-all + re-add-all)
-- when children swap positions. Uses different widget types at
-- each position so we can verify visual order via uiautomator.
--
-- State0: Column [Button "FIRST", Text "SECOND", Text "THIRD"]
-- State1: Column [Text "THIRD", Text "SECOND", Button "FIRST"]
--
-- After switch, verifies that THIRD appears before FIRST in the
-- uiautomator dump (top-to-bottom order matches LinearLayout order).
module Main where

import Data.IORef (IORef, newIORef, readIORef, modifyIORef')
import Data.Text qualified as Text
import Foreign.Ptr (Ptr)
import Hatter (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), newActionState, runActionM, createAction, Action)
import Hatter.AppContext (AppContext)
import Hatter.Widget (ButtonConfig(..), Widget(..), text)

data TestState = OrderABC | OrderCBA
  deriving (Show, Eq)

main :: IO (Ptr AppContext)
main = do
  platformLog "ColumnChildReorder demo registered"
  actionState <- newActionState
  testState <- newIORef OrderABC
  reorderAction <- runActionM actionState $
    createAction (modifyIORef' testState toggle)
  noopAction <- runActionM actionState $
    createAction (pure ())
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> reorderView testState reorderAction noopAction
    , maActionState = actionState
    }

toggle :: TestState -> TestState
toggle OrderABC = OrderCBA
toggle OrderCBA = OrderABC

reorderView :: IORef TestState -> Action -> Action -> IO Widget
reorderView testState reorderAction noopAction = do
  state <- readIORef testState
  platformLog ("Reorder state: " <> Text.pack (show state))
  let children = case state of
        OrderABC ->
          [ Button ButtonConfig { bcLabel = "ITEM_FIRST", bcAction = noopAction, bcFontConfig = Nothing }
          , text "ITEM_SECOND"
          , text "ITEM_THIRD"
          ]
        OrderCBA ->
          [ text "ITEM_THIRD"
          , text "ITEM_SECOND"
          , Button ButtonConfig { bcLabel = "ITEM_FIRST", bcAction = noopAction, bcFontConfig = Nothing }
          ]
  pure $ Column
    ( Button ButtonConfig
        { bcLabel = "Reorder"
        , bcAction = reorderAction
        , bcFontConfig = Nothing
        }
    : children
    )
