{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the bottom-sheet-demo test app.
--
-- Used by the emulator and simulator bottom sheet integration tests.
-- Starts directly in bottom-sheet-demo mode so no runtime switching is needed.
module Main where

import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (pack)
import Foreign.Ptr (Ptr)
import HaskellMobile
  ( MobileApp(..)
  , Action
  , BottomSheetConfig(..)
  , BottomSheetState(..)
  , AppContext
  , startMobileApp
  , derefAppContext
  , platformLog
  , showBottomSheet
  , loggingMobileContext
  , newActionState
  , runActionM
  , createAction
  )
import HaskellMobile.AppContext (AppContext(..))
import HaskellMobile.Widget (ButtonConfig(..), TextConfig(..), Widget(..))

main :: IO (Ptr AppContext)
main = do
  actionState <- newActionState
  bssRef <- newIORef (Nothing :: Maybe BottomSheetState)
  onShowActions <- runActionM actionState $
    createAction $ do
      Just bottomSheetState <- readIORef bssRef
      showBottomSheet bottomSheetState
        BottomSheetConfig
          { bscTitle = "Choose Action"
          , bscItems = ["Edit", "Delete", "Share"]
          }
        (\action -> platformLog ("BottomSheet result: " <> pack (show action)))
  ctxPtr <- startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> bottomSheetDemoView onShowActions
    , maActionState = actionState
    }
  appCtx <- derefAppContext ctxPtr
  writeIORef bssRef (Just (acBottomSheetState appCtx))
  platformLog "BottomSheet demo app registered"
  pure ctxPtr

-- | Builds a Column with a label and a "Show Actions" button.
bottomSheetDemoView :: Action -> IO Widget
bottomSheetDemoView onShowActions = pure $ Column
  [ Text TextConfig { tcLabel = "BottomSheet Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel      = "Show Actions"
      , bcAction     = onShowActions
      , bcFontConfig = Nothing
      }
  ]
