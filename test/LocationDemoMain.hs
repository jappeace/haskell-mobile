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

import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (pack)
import Foreign.Ptr (Ptr)
import HaskellMobile
  ( MobileApp(..)
  , Action
  , LocationState(..)
  , startMobileApp
  , derefAppContext
  , platformLog
  , startLocationUpdates
  , stopLocationUpdates
  , loggingMobileContext
  , AppContext
  , newActionState
  , runActionM
  , createAction
  )
import HaskellMobile.AppContext (AppContext(..))
import HaskellMobile.Location (LocationData(..))
import HaskellMobile.Widget (ButtonConfig(..), TextConfig(..), Widget(..))

main :: IO (Ptr AppContext)
main = do
  platformLog "Location demo app registered"
  actionState <- newActionState
  locStateRef <- newIORef (Nothing :: Maybe LocationState)
  (onStartLocation, onStopLocation) <- runActionM actionState $ do
    start <- createAction $ do
      Just locationState <- readIORef locStateRef
      startLocationUpdates locationState $ \locationData ->
        platformLog ("Location: " <> pack (show (ldLatitude locationData))
                    <> "," <> pack (show (ldLongitude locationData))
                    <> " alt=" <> pack (show (ldAltitude locationData))
                    <> " acc=" <> pack (show (ldAccuracy locationData)))
      platformLog "Location updates started"
    stop <- createAction $ do
      Just locationState <- readIORef locStateRef
      stopLocationUpdates locationState
      platformLog "Location updates stopped"
    pure (start, stop)
  ctxPtr <- startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> locationDemoView onStartLocation onStopLocation
    , maActionState = actionState
    }
  appCtx <- derefAppContext ctxPtr
  writeIORef locStateRef (Just (acLocationState appCtx))
  pure ctxPtr

-- | Builds a Column with a label and start/stop location buttons.
locationDemoView :: Action -> Action -> IO Widget
locationDemoView onStartLocation onStopLocation = pure $ Column
  [ Text TextConfig { tcLabel = "Location Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel = "Start Location", bcAction = onStartLocation, bcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel = "Stop Location", bcAction = onStopLocation, bcFontConfig = Nothing }
  ]
