{-# LANGUAGE OverloadedStrings #-}
-- | Reproducer: Styled wrapper with child type change (same style).
--
-- When a Styled wraps a child that changes widget type (e.g. Text→Button)
-- but the style stays the same, the diff algorithm skips reapplying the
-- style because newStyle == oldStyle. The new native node never receives
-- the styling (e.g. background color, text color).
--
-- This test switches between two screens where the Styled wrapper keeps
-- the same style but the inner widget changes type. The test verifies
-- that the style is visually applied after the switch by checking that
-- the correct widget types exist with the expected labels AND that the
-- platform logs show the style being applied (or not).
module Main where

import Data.IORef (IORef, newIORef, readIORef, modifyIORef')
import Data.Text qualified as Text
import Data.Word (Word8)
import Foreign.Ptr (Ptr)
import Hatter (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), newActionState, runActionM, createAction, Action)
import Hatter.AppContext (AppContext)
import Hatter.Widget (ButtonConfig(..), TextConfig(..), Widget(..), WidgetStyle(..), Color(..), defaultStyle)

data Screen = ScreenA | ScreenB
  deriving (Show, Eq)

main :: IO (Ptr AppContext)
main = do
  platformLog "StyledTypeChange demo registered"
  actionState <- newActionState
  screenState <- newIORef ScreenA
  switchAction <- runActionM actionState $
    createAction (modifyIORef' screenState toggle)
  noopAction <- runActionM actionState $
    createAction (pure ())
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> styledTypeChangeView screenState switchAction noopAction
    , maActionState = actionState
    }

toggle :: Screen -> Screen
toggle ScreenA = ScreenB
toggle ScreenB = ScreenA

-- | A red background style that stays constant across screen switches.
redBackground :: WidgetStyle
redBackground = defaultStyle
  { wsBackgroundColor = Just (Color 255 0 0 (255 :: Word8))
  , wsTextColor       = Just (Color 255 255 255 (255 :: Word8))
  }

-- | The view: a Column with a switch button and a Styled widget.
--
-- ScreenA: Styled redBackground (Text "STYLED_TEXT")
-- ScreenB: Styled redBackground (Button "STYLED_BUTTON")
--
-- The style stays the same but the child type changes.
-- Bug: the new Button node never gets the red background because
-- applyStyle is conditional on style inequality.
styledTypeChangeView :: IORef Screen -> Action -> Action -> IO Widget
styledTypeChangeView screenState switchAction noopAction = do
  screen <- readIORef screenState
  platformLog ("Current screen: " <> Text.pack (show screen))
  let styledChild = case screen of
        ScreenA -> Styled redBackground
          (Text TextConfig
            { tcLabel = "STYLED_TEXT"
            , tcFontConfig = Nothing
            })
        ScreenB -> Styled redBackground
          (Button ButtonConfig
            { bcLabel = "STYLED_BUTTON"
            , bcAction = noopAction
            , bcFontConfig = Nothing
            })
  pure $ Column
    [ Button ButtonConfig
        { bcLabel = "Switch screen"
        , bcAction = switchAction
        , bcFontConfig = Nothing
        }
    , styledChild
    ]
