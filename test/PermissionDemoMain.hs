{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the permission-demo test app.
--
-- Used by the emulator and simulator permission integration tests.
-- Starts directly in permission-demo mode so no runtime switching is needed.
module Main where

import Data.Text (pack)
import HaskellMobile
  ( MobileApp(..)
  , AppState(..)
  , Permission(..)
  , PermissionStatus(..)
  , runMobileApp
  , platformLog
  , globalAppState
  , requestPermission
  , loggingMobileContext
  )
import HaskellMobile.Widget (ButtonConfig(..), TextConfig(..), Widget(..))

main :: IO ()
main = do
  runMobileApp permissionDemoApp
  platformLog "Permission demo app registered"

-- | Permission demo: requests camera permission on button tap.
-- Used by integration tests to verify the permission FFI bridge end-to-end.
permissionDemoApp :: MobileApp
permissionDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = permissionDemoView
  }

-- | Builds a Column with a label and a "Request Camera" button.
-- The button's callback ID is 0 (first registered), matching --autotest dispatch.
permissionDemoView :: IO Widget
permissionDemoView = pure $ Column
  [ Text TextConfig { tcLabel = "Permission Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel = "Request Camera"
      , bcAction = requestPermission (appPermissionState globalAppState) PermissionCamera $ \status ->
          platformLog ("Permission result: " <> pack (show status))
      , bcFontConfig = Nothing
      }
  ]
