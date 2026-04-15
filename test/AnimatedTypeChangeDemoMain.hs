{-# LANGUAGE OverloadedStrings #-}
-- | Reproducer: changing widget type inside an Animated wrapper.
--
-- When an Animated wraps a child that changes widget type
-- (e.g. Text→Button), the diff algorithm destroys the old node
-- and creates a new one. The Animated config is preserved in the
-- RenderedAnimated wrapper, but we need to verify the new child
-- actually renders correctly on the native platform.
--
-- State0: Animated (Text "ANIM_TEXT")
-- State1: Animated (Button "ANIM_BUTTON")
--
-- Verifies the new widget is visible and the old one is gone.
module Main where

import Data.IORef (IORef, newIORef, readIORef, modifyIORef')
import Data.Text qualified as Text
import Foreign.Ptr (Ptr)
import Hatter (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), newActionState, runActionM, createAction, Action)
import Hatter.AppContext (AppContext)
import Hatter.Widget (ButtonConfig(..), TextConfig(..), Widget(..), AnimatedConfig(..), Easing(..))

data Screen = ScreenA | ScreenB
  deriving (Show, Eq)

main :: IO (Ptr AppContext)
main = do
  platformLog "AnimatedTypeChange demo registered"
  actionState <- newActionState
  screenState <- newIORef ScreenA
  switchAction <- runActionM actionState $
    createAction (modifyIORef' screenState toggle)
  noopAction <- runActionM actionState $
    createAction (pure ())
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> animatedTypeChangeView screenState switchAction noopAction
    , maActionState = actionState
    }

toggle :: Screen -> Screen
toggle ScreenA = ScreenB
toggle ScreenB = ScreenA

animConfig :: AnimatedConfig
animConfig = AnimatedConfig
  { anDuration = 300
  , anEasing   = EaseInOut
  }

animatedTypeChangeView :: IORef Screen -> Action -> Action -> IO Widget
animatedTypeChangeView screenState switchAction noopAction = do
  screen <- readIORef screenState
  platformLog ("Animated screen: " <> Text.pack (show screen))
  let animChild = case screen of
        ScreenA -> Animated animConfig
          (Text TextConfig
            { tcLabel = "ANIM_TEXT"
            , tcFontConfig = Nothing
            })
        ScreenB -> Animated animConfig
          (Button ButtonConfig
            { bcLabel = "ANIM_BUTTON"
            , bcAction = noopAction
            , bcFontConfig = Nothing
            })
  pure $ Column
    [ Button ButtonConfig
        { bcLabel = "Switch animated"
        , bcAction = switchAction
        , bcFontConfig = Nothing
        }
    , animChild
    ]
