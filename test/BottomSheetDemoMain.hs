{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the bottom-sheet-demo test app.
--
-- Used by the emulator and simulator bottom sheet integration tests.
-- Starts directly in bottom-sheet-demo mode so no runtime switching is needed.
module Main where

import Data.Text (pack)
import Foreign.Ptr (Ptr)
import HaskellMobile
  ( MobileApp(..)
  , UserState(..)
  , BottomSheetAction(..)
  , BottomSheetConfig(..)
  , AppContext
  , startMobileApp
  , platformLog
  , showBottomSheet
  , loggingMobileContext
  )
import HaskellMobile.Widget (ButtonConfig(..), TextConfig(..), User, Widget(..))

main :: IO (Ptr AppContext)
main = do
  ctxPtr <- startMobileApp bottomSheetDemoApp
  platformLog "BottomSheet demo app registered"
  pure ctxPtr

-- | Bottom sheet demo: shows action menu on button tap.
-- Used by integration tests to verify the bottom sheet FFI bridge end-to-end.
bottomSheetDemoApp :: MobileApp
bottomSheetDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = bottomSheetDemoView
  }

-- | Builds a Column with a label and a "Show Actions" button.
bottomSheetDemoView :: UserState -> IO (Widget User)
bottomSheetDemoView userState = pure $ Column
  [ Text TextConfig { tcLabel = "BottomSheet Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel = "Show Actions"
      , bcAction = showBottomSheet (userBottomSheetState userState)
          BottomSheetConfig
            { bscTitle = "Choose Action"
            , bscItems = ["Edit", "Delete", "Share"]
            }
          (\action -> platformLog ("BottomSheet result: " <> pack (show action)))
      , bcFontConfig = Nothing
      }
  ]
