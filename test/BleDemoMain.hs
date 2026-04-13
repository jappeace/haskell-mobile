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

import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (pack)
import Foreign.Ptr (Ptr)
import Hatter
  ( MobileApp(..)
  , Action
  , BleState(..)
  , startMobileApp
  , derefAppContext
  , platformLog
  , checkBleAdapter
  , startBleScan
  , stopBleScan
  , loggingMobileContext
  , AppContext
  , newActionState
  , runActionM
  , createAction
  )
import Hatter.AppContext (AppContext(..))
import Hatter.Widget (ButtonConfig(..), TextConfig(..), Widget(..))

main :: IO (Ptr AppContext)
main = do
  platformLog "BLE demo app registered"
  actionState <- newActionState
  bleStateRef <- newIORef (Nothing :: Maybe BleState)
  (onCheckAdapter, onStartScan, onStopScan) <- runActionM actionState $ do
    check <- createAction $ do
      adapterStatus <- checkBleAdapter
      platformLog ("BLE adapter: " <> pack (show adapterStatus))
    start <- createAction $ do
      Just bleState <- readIORef bleStateRef
      startBleScan bleState $ \scanResult ->
        platformLog ("BLE scan result: " <> pack (show scanResult))
      platformLog "BLE scan started"
    stop <- createAction $ do
      Just bleState <- readIORef bleStateRef
      stopBleScan bleState
      platformLog "BLE scan stopped"
    pure (check, start, stop)
  ctxPtr <- startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> bleDemoView onCheckAdapter onStartScan onStopScan
    , maActionState = actionState
    }
  appCtx <- derefAppContext ctxPtr
  writeIORef bleStateRef (Just (acBleState appCtx))
  pure ctxPtr

-- | Builds a Column with a label, adapter check button, and scan buttons.
bleDemoView :: Action -> Action -> Action -> IO Widget
bleDemoView onCheckAdapter onStartScan onStopScan = pure $ Column
  [ Text TextConfig { tcLabel = "BLE Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel = "Check Adapter", bcAction = onCheckAdapter, bcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel = "Start Scan", bcAction = onStartScan, bcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel = "Stop Scan", bcAction = onStopScan, bcFontConfig = Nothing }
  ]
