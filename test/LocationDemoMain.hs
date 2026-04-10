{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the location-demo test app.
--
-- Used by the emulator and simulator location integration tests.
-- Starts directly in location-demo mode so no runtime switching is needed.
--
-- The view function is kept pure (no IO / FFI calls) to avoid
-- JNI reentrancy issues on armv7a.  Location FFI calls run on
-- button press instead.
module Main where

import Data.Text (pack)
import Foreign.Ptr (Ptr)
import HaskellMobile
  ( MobileApp(..)
  , UserState(..)
  , startMobileApp
  , platformLog
  , startLocationUpdates
  , stopLocationUpdates
  , loggingMobileContext
  , AppContext
  )
import HaskellMobile.Location (LocationData(..))
import HaskellMobile.Widget (ButtonConfig(..), TextConfig(..), User, Widget(..))

main :: IO (Ptr AppContext)
main = do
  platformLog "Location demo app registered"
  startMobileApp locationDemoApp

-- | Location demo: provides start/stop location update buttons.
-- Used by integration tests to verify the location FFI bridge end-to-end.
locationDemoApp :: MobileApp
locationDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = locationDemoView
  }

-- | Builds a Column with a label and start/stop location buttons.
-- The view itself is pure — all location FFI calls happen in button
-- callbacks to avoid JNI reentrancy issues during rendering.
locationDemoView :: UserState -> IO (Widget User)
locationDemoView userState = pure $ Column
  [ Text TextConfig { tcLabel = "Location Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel = "Start Location"
      , bcAction = do
          startLocationUpdates (userLocationState userState) $ \locationData ->
            platformLog ("Location: " <> pack (show (ldLatitude locationData))
                        <> "," <> pack (show (ldLongitude locationData))
                        <> " alt=" <> pack (show (ldAltitude locationData))
                        <> " acc=" <> pack (show (ldAccuracy locationData)))
          platformLog "Location updates started"
      , bcFontConfig = Nothing
      }
  , Button ButtonConfig
      { bcLabel = "Stop Location"
      , bcAction = do
          stopLocationUpdates (userLocationState userState)
          platformLog "Location updates stopped"
      , bcFontConfig = Nothing
      }
  ]
