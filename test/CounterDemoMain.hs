{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the counter-demo test app.
--
-- Used by the emulator and simulator integration tests (Phase 1).
-- Tests lifecycle events, UI rendering, and button interaction sequences.
module Main where

import Data.IORef (IORef, newIORef, readIORef, modifyIORef')
import Data.Text qualified as Text
import Foreign.Ptr (Ptr)
import HaskellMobile (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), AppContext, newActionState, runActionM, createAction, Action)
import HaskellMobile.Widget (ButtonConfig(..), Color(..), FontConfig(..), TextAlignment(..), TextConfig(..), Widget(..), WidgetStyle(..))

main :: IO (Ptr AppContext)
main = do
  platformLog "Counter demo app registered"
  actionState <- newActionState
  counterState <- newIORef (0 :: Int)
  (onIncrement, onDecrement) <- runActionM actionState $ do
    inc <- createAction (modifyIORef' counterState (+ 1))
    dec <- createAction (modifyIORef' counterState (subtract 1))
    pure (inc, dec)
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> counterView counterState onIncrement onDecrement
    , maActionState = actionState
    }

-- | Counter view: displays current count with styled label and +/- buttons.
counterView :: IORef Int -> Action -> Action -> IO Widget
counterView counterState onIncrement onDecrement = do
  n <- readIORef counterState
  pure $ Column
    [ Styled (WidgetStyle (Just 16.0) (Just AlignCenter) (Just (Color 255 0 0 255)) (Just (Color 0 255 0 255)))
        (Text TextConfig
          { tcLabel      = "Counter: " <> Text.pack (show n)
          , tcFontConfig = Just (FontConfig 24.0)
          })
    , Row [ Button ButtonConfig
              { bcLabel = "+", bcAction = onIncrement, bcFontConfig = Nothing }
          , Button ButtonConfig
              { bcLabel = "-", bcAction = onDecrement, bcFontConfig = Nothing }
          ]
    ]
