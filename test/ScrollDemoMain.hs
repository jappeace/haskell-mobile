{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the scroll-demo test app.
--
-- Used by the emulator and simulator ScrollView integration tests.
-- Starts directly in scroll-demo mode so no runtime switching is needed.
module Main where

import Data.Text qualified as Text
import Foreign.Ptr (Ptr)
import HaskellMobile (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), AppContext)
import HaskellMobile.Widget (ButtonConfig(..), TextConfig(..), Widget(..))

main :: IO (Ptr AppContext)
main = do
  platformLog "Scroll demo app registered"
  startMobileApp scrollDemoApp

-- | Scroll demo: 20 text items + a button at the bottom inside a ScrollView.
-- Used by integration tests to verify the ScrollView FFI binding end-to-end.
scrollDemoApp :: MobileApp
scrollDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = \_userState -> scrollDemoView
  }

-- | Builds a ScrollView containing 20 text items followed by a button.
-- The button's callback ID is 0 (first registered), matching the --autotest dispatch.
scrollDemoView :: IO Widget
scrollDemoView = pure $ ScrollView
  [ Column
    ( map (\itemNumber -> Text TextConfig
        { tcLabel = "Item " <> Text.pack (show (itemNumber :: Int)), tcFontConfig = Nothing }) [1..20]
    ++ [Button ButtonConfig
        { bcLabel = "Reached Bottom", bcAction = pure (), bcFontConfig = Nothing }]
    )
  ]
