{-# LANGUAGE OverloadedStrings #-}
-- | Default implementation of the mobile app.
-- Provides 'loggingMobileContext' as the application context and a simple
-- counter demo as the default UI.
module HaskellMobile.App (mobileApp) where

import Data.IORef (IORef, newIORef, readIORef, modifyIORef')
import Data.Text (pack)
import HaskellMobile.Types (MobileApp(..))
import HaskellMobile.Lifecycle (loggingMobileContext)
import HaskellMobile.Widget (Widget(..))
import System.IO.Unsafe (unsafePerformIO)

-- | The default mobile app — logs every lifecycle event and shows a counter.
mobileApp :: MobileApp
mobileApp = MobileApp
  { maContext = loggingMobileContext
  , maView = counterView
  }

-- | Global counter state for the demo app.
counter :: IORef Int
counter = unsafePerformIO (newIORef 0)
{-# NOINLINE counter #-}

-- | Counter demo: displays current count with +/- buttons.
counterView :: IO Widget
counterView = do
  n <- readIORef counter
  pure $ Column
    [ Text ("Counter: " <> pack (show n))
    , Row [ Button "+" (modifyIORef' counter (+ 1))
          , Button "-" (modifyIORef' counter (subtract 1))
          ]
    ]
