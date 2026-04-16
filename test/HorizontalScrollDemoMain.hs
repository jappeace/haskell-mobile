{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the horizontal-scroll-demo test app.
--
-- Used by the emulator and simulator integration tests.
-- Displays a scrollable Row containing 20 buttons.
-- Tapping the last button logs "Click dispatched".
module Main where

import Data.Text qualified as Text
import Foreign.Ptr (Ptr)
import Hatter (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), newActionState, runActionM, createAction, Action)
import Hatter.AppContext (AppContext)
import Hatter.Widget (ButtonConfig(..), LayoutSettings(..), Widget(..), button)

main :: IO (Ptr AppContext)
main = do
  platformLog "Horizontal scroll demo app registered"
  actionState <- newActionState
  (noopAction, onReachedEnd) <- runActionM actionState $ do
    noop <- createAction (pure ())
    reachedEnd <- createAction (pure ())
    pure (noop, reachedEnd)
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> horizontalScrollDemoView noopAction onReachedEnd
    , maActionState = actionState
    }

-- | Builds a scrollable Row containing 20 buttons followed by a "Reached End" button.
horizontalScrollDemoView :: Action -> Action -> IO Widget
horizontalScrollDemoView noopAction onReachedEnd = pure $ Row (LayoutSettings
  ( map (\itemNumber -> button ("Item " <> Text.pack (show (itemNumber :: Int))) noopAction) [1..20]
  ++ [Button ButtonConfig
      { bcLabel = "Reached End", bcAction = onReachedEnd, bcFontConfig = Nothing }]
  ) True)
