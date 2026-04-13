{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the network-status-demo test app.
--
-- Used by the emulator and simulator network status integration tests.
-- Starts directly in network-status-demo mode so no runtime switching
-- is needed.
--
-- The view function is kept pure (no IO / FFI calls) to avoid
-- JNI reentrancy issues on armv7a.  Network status FFI calls run on
-- button press instead.
module Main where

import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (pack)
import Foreign.Ptr (Ptr)
import Hatter
  ( MobileApp(..)
  , Action
  , NetworkStatusState(..)
  , startMobileApp
  , derefAppContext
  , platformLog
  , startNetworkMonitoring
  , stopNetworkMonitoring
  , loggingMobileContext
  , AppContext
  , newActionState
  , runActionM
  , createAction
  )
import Hatter.AppContext (AppContext(..))
import Hatter.NetworkStatus (NetworkStatus(..), NetworkTransport(..))
import Hatter.Widget (ButtonConfig(..), TextConfig(..), Widget(..))

main :: IO (Ptr AppContext)
main = do
  platformLog "Network status demo app registered"
  actionState <- newActionState
  nssRef <- newIORef (Nothing :: Maybe NetworkStatusState)
  (onStartMonitoring, onStopMonitoring) <- runActionM actionState $ do
    start <- createAction $ do
      Just networkStatusState <- readIORef nssRef
      startNetworkMonitoring networkStatusState $ \networkStatus ->
        platformLog ("Network: connected=" <> pack (show (nsConnected networkStatus))
                    <> " transport=" <> pack (show (nsTransport networkStatus)))
      platformLog "Network monitoring started"
    stop <- createAction $ do
      Just networkStatusState <- readIORef nssRef
      stopNetworkMonitoring networkStatusState
      platformLog "Network monitoring stopped"
    pure (start, stop)
  ctxPtr <- startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> networkStatusDemoView onStartMonitoring onStopMonitoring
    , maActionState = actionState
    }
  appCtx <- derefAppContext ctxPtr
  writeIORef nssRef (Just (acNetworkStatusState appCtx))
  pure ctxPtr

-- | Builds a Column with a label and start/stop monitoring buttons.
networkStatusDemoView :: Action -> Action -> IO Widget
networkStatusDemoView onStartMonitoring onStopMonitoring = pure $ Column
  [ Text TextConfig { tcLabel = "Network Status Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel = "Start Monitoring", bcAction = onStartMonitoring, bcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel = "Stop Monitoring", bcAction = onStopMonitoring, bcFontConfig = Nothing }
  ]
