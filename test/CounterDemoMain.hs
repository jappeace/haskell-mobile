{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the counter-demo test app.
--
-- Used by the emulator and simulator integration tests (Phase 1).
-- Tests lifecycle events, UI rendering, and button interaction sequences.
module Main where

import Data.IORef (IORef, newIORef, readIORef, modifyIORef')
import Data.Text qualified as Text
import Foreign.Ptr (Ptr)
import Hatter (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), newActionState, runActionM, createAction, Action)
import Hatter.AppContext (AppContext)
import Hatter.Widget (ButtonConfig(..), Color(..), FontConfig(..), TextAlignment(..), TextConfig(..), Widget(..), WidgetStyle(..), column, row)

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
  pure $ column
    [ Styled (WidgetStyle (Just 16.0) (Just AlignCenter) (Just (Color 255 0 0 255)) (Just (Color 0 255 0 255)) Nothing Nothing Nothing)
        (Text TextConfig
          { tcLabel      = "Counter: " <> Text.pack (show n)
          , tcFontConfig = Just (FontConfig 24.0)
          })
    , row [ Button ButtonConfig
              { bcLabel = "+", bcAction = onIncrement, bcFontConfig = Nothing }
          , Button ButtonConfig
              { bcLabel = "-", bcAction = onDecrement, bcFontConfig = Nothing }
          ]
    ]
