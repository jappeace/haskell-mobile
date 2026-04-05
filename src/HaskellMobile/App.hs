{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}
-- | Default implementation of the mobile app.
-- Provides 'loggingMobileContext' as the application context and a simple
-- counter demo as the default UI.
module HaskellMobile.App (mobileApp, scrollDemoApp, haskellUseScrollDemo) where

import Data.IORef (IORef, newIORef, readIORef, modifyIORef')
import Data.Text (pack)
import HaskellMobile.Types (MobileApp(..), runMobileApp)
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

-- | Scroll demo: 20 text items + a button at the bottom inside a ScrollView.
-- Used by integration tests to verify the ScrollView FFI binding end-to-end.
scrollDemoApp :: MobileApp
scrollDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = scrollDemoView
  }

-- | Builds a ScrollView containing 20 text items followed by a button.
-- The button's callback ID is 0 (first registered), matching the --autotest dispatch.
scrollDemoView :: IO Widget
scrollDemoView = pure $ ScrollView
  [ Column
    ( map (\itemNumber -> Text ("Item " <> pack (show (itemNumber :: Int)))) [1..20]
    ++ [Button "Reached Bottom" (pure ())]
    )
  ]

-- | Switch the running app to the scroll demo. Called via JNI (Android) or
-- direct FFI (iOS) when the test harness requests scroll-demo mode.
haskellUseScrollDemo :: IO ()
haskellUseScrollDemo = runMobileApp scrollDemoApp

foreign export ccall haskellUseScrollDemo :: IO ()
