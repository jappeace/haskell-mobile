{-# LANGUAGE OverloadedStrings #-}
-- | Reproducer for issue #168: switching between two ScrollViews
-- via state causes the diff algorithm to "mix" their content.
--
-- The two screens use DIFFERENT widget types at the same child
-- positions (Text vs Button) so that the diff engine calls
-- replaceNode (destroy old + create new) instead of in-place update.
-- This triggers the bug: android_destroy_node frees the JNI ref
-- but doesn't remove the native View from its parent, so orphaned
-- views linger in the ScrollView after switching.
module Main where

import Data.IORef (IORef, newIORef, readIORef, modifyIORef')
import Data.Text qualified as Text
import Foreign.Ptr (Ptr)
import Hatter (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), newActionState, runActionM, createAction, Action)
import Hatter.AppContext (AppContext)
import Hatter.Widget (ButtonConfig(..), LayoutSettings(..), Widget(..), column, text)

data Screen = ScreenA | ScreenB
  deriving (Show, Eq)

main :: IO (Ptr AppContext)
main = do
  platformLog "ScrollView switch demo registered"
  actionState <- newActionState
  screenState <- newIORef ScreenA
  switchAction <- runActionM actionState $
    createAction (modifyIORef' screenState toggle)
  -- A no-op action for buttons that exist only to change widget types
  noopAction <- runActionM actionState $
    createAction (pure ())
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> switchDemoView screenState switchAction noopAction
    , maActionState = actionState
    }

toggle :: Screen -> Screen
toggle ScreenA = ScreenB
toggle ScreenB = ScreenA

-- | The view function: a Column with a switch button and a ScrollView
-- whose content depends on the current screen.
--
-- ScreenA has [Button, Text, Text] and ScreenB has [Text, Button].
-- The type mismatch at position 0 (Button→Text) and position 1
-- (Text→Button) forces replaceNode, which on Android leaves orphaned
-- views in the native hierarchy because android_destroy_node doesn't
-- call removeView on the parent.
switchDemoView :: IORef Screen -> Action -> Action -> IO Widget
switchDemoView screenState switchAction noopAction = do
  screen <- readIORef screenState
  platformLog ("Current screen: " <> Text.pack (show screen))
  let inner = case screen of
        ScreenA -> Column (LayoutSettings
          [ Button ButtonConfig
              { bcLabel = "SCREENA_BTN"
              , bcAction = noopAction
              , bcFontConfig = Nothing
              }
          , text "SCREENA_TXT1"
          , text "SCREENA_TXT2"
          ] True)
        ScreenB -> Column (LayoutSettings
          [ text "SCREENB_TXT1"
          , Button ButtonConfig
              { bcLabel = "SCREENB_BTN"
              , bcAction = noopAction
              , bcFontConfig = Nothing
              }
          ] True)
  pure $ column
    [ Button ButtonConfig
        { bcLabel = "Switch screen"
        , bcAction = switchAction
        , bcFontConfig = Nothing
        }
    , inner
    ]
