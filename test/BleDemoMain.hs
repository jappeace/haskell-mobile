{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the BLE-demo test app.
--
-- Used by the emulator and simulator BLE integration tests.
-- Starts directly in BLE-demo mode so no runtime switching is needed.
--
-- The view function is kept pure (no IO / FFI calls) to avoid
-- JNI reentrancy issues on armv7a.  The adapter check runs on
-- button press instead.
module Main where

import Data.Text (pack)
import Foreign.Ptr (Ptr)
import HaskellMobile
  ( MobileApp(..)
  , UserState(..)
  , startMobileApp
  , platformLog
  , checkBleAdapter
  , startBleScan
  , stopBleScan
  , loggingMobileContext
  , AppContext
  )
import HaskellMobile.Widget (ButtonConfig(..), TextConfig(..), Widget(..))

main :: IO (Ptr AppContext)
main = do
  platformLog "BLE demo app registered"
  startMobileApp bleDemoApp

-- | BLE demo: provides adapter check and scan start/stop buttons.
-- Used by integration tests to verify the BLE FFI bridge end-to-end.
bleDemoApp :: MobileApp
bleDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = bleDemoView
  }

-- | Builds a Column with a label, adapter check button, and scan buttons.
-- The view itself is pure — all BLE FFI calls happen in button callbacks
-- to avoid JNI reentrancy issues during rendering.
bleDemoView :: UserState -> IO Widget
bleDemoView userState = pure $ Column
  [ Text TextConfig { tcLabel = "BLE Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel = "Check Adapter"
      , bcAction = do
          adapterStatus <- checkBleAdapter
          platformLog ("BLE adapter: " <> pack (show adapterStatus))
      , bcFontConfig = Nothing
      }
  , Button ButtonConfig
      { bcLabel = "Start Scan"
      , bcAction = do
          startBleScan (userBleState userState) $ \scanResult ->
            platformLog ("BLE scan result: " <> pack (show scanResult))
          platformLog "BLE scan started"
      , bcFontConfig = Nothing
      }
  , Button ButtonConfig
      { bcLabel = "Stop Scan"
      , bcAction = do
          stopBleScan (userBleState userState)
          platformLog "BLE scan stopped"
      , bcFontConfig = Nothing
      }
  ]
