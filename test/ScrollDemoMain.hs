{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the scroll-demo test app.
--
-- Used by the emulator and simulator ScrollView integration tests.
-- Starts directly in scroll-demo mode so no runtime switching is needed.
module Main where

import Data.Text qualified as Text
import Foreign.Ptr (Ptr)
import Hatter (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), newActionState, runActionM, createAction, Action)
import Hatter.AppContext (AppContext)
import Hatter.Widget (ButtonConfig(..), LayoutSettings(..), TextConfig(..), Widget(..), column)

main :: IO (Ptr AppContext)
main = do
  platformLog "Scroll demo app registered"
  actionState <- newActionState
  onReachedBottom <- runActionM actionState $
    createAction (pure ())
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> scrollDemoView onReachedBottom
    , maActionState = actionState
    }

-- | Builds a scrollable Column containing 20 text items followed by a button.
scrollDemoView :: Action -> IO Widget
scrollDemoView onReachedBottom = pure $ Column (LayoutSettings
  [ column
    ( map (\itemNumber -> Text TextConfig
        { tcLabel = "Item " <> Text.pack (show (itemNumber :: Int)), tcFontConfig = Nothing }) [1..20]
    ++ [Button ButtonConfig
        { bcLabel = "Reached Bottom", bcAction = onReachedBottom, bcFontConfig = Nothing }]
    )
  ] True)
