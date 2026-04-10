{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the counter-demo test app.
--
-- Used by the emulator and simulator integration tests (Phase 1).
-- Tests lifecycle events, UI rendering, and button interaction sequences.
module Main where

import Data.IORef (IORef, newIORef, readIORef, modifyIORef')
import Data.Text qualified as Text
import Foreign.Ptr (Ptr)
import HaskellMobile (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), AppContext)
import HaskellMobile.Widget (ButtonConfig(..), Color(..), FontConfig(..), TextAlignment(..), TextConfig(..), Widget(..), WidgetStyle(..))
import System.IO.Unsafe (unsafePerformIO)

main :: IO (Ptr AppContext)
main = do
  platformLog "Counter demo app registered"
  startMobileApp counterDemoApp

-- | Counter demo: logs every lifecycle event and shows a counter with +/- buttons.
counterDemoApp :: MobileApp
counterDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = \_userState -> counterView
  }

-- | Global counter state for the demo app.
counterState :: IORef Int
counterState = unsafePerformIO (newIORef 0)
{-# NOINLINE counterState #-}

-- | Counter view: displays current count with styled label and +/- buttons.
counterView :: IO Widget
counterView = do
  n <- readIORef counterState
  pure $ Column
    [ Styled (WidgetStyle (Just 16.0) (Just AlignCenter) (Just (Color 255 0 0 255)) (Just (Color 0 255 0 255)))
        (Text TextConfig
          { tcLabel      = "Counter: " <> Text.pack (show n)
          , tcFontConfig = Just (FontConfig 24.0)
          })
    , Row [ Button ButtonConfig
              { bcLabel = "+", bcAction = modifyIORef' counterState (+ 1), bcFontConfig = Nothing }
          , Button ButtonConfig
              { bcLabel = "-", bcAction = modifyIORef' counterState (subtract 1), bcFontConfig = Nothing }
          ]
    ]
