{-# LANGUAGE OverloadedStrings #-}
-- | Default implementation of the @HaskellMobile.App@ Backpack signature.
-- Provides 'loggingMobileContext' as the application context and a simple
-- counter demo as the default UI.
module HaskellMobile.App (appContext, appView) where

import Data.IORef (IORef, newIORef, readIORef, modifyIORef')
import Data.Text (pack)
import HaskellMobile.Lifecycle (MobileContext, loggingMobileContext)
import HaskellMobile.Widget (Widget(..))
import System.IO.Unsafe (unsafePerformIO)

-- | The default application context — logs every lifecycle event.
appContext :: MobileContext
appContext = loggingMobileContext

-- | Global counter state for the demo app.
counter :: IORef Int
counter = unsafePerformIO (newIORef 0)
{-# NOINLINE counter #-}

-- | Counter demo: displays current count with +/- buttons.
appView :: IO Widget
appView = do
  n <- readIORef counter
  pure $ Column
    [ Text ("Counter: " <> pack (show n))
    , Row [ Button "+" (modifyIORef' counter (+ 1))
          , Button "-" (modifyIORef' counter (subtract 1))
          ]
    ]
