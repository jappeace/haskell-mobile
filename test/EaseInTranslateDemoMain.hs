{-# LANGUAGE OverloadedStrings #-}
-- | Integration test app: EaseIn translate animation.
--
-- A text label starts at position (0, 0).  Tapping "Move Text"
-- animates it to (120, 80) over 400ms using EaseIn.  Tapping
-- "Reset" animates it back.  The app logs position changes so
-- the Android emulator test can assert via logcat.
module Main where

import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (pack)
import Foreign.Ptr (Ptr)
import Hatter
  ( MobileApp(..)
  , UserState(..)
  , AnimatedConfig(..)
  , Easing(..)
  , startMobileApp
  , newActionState
  , runActionM
  , createAction
  , loggingMobileContext
  , platformLog
  )
import Hatter.AppContext (AppContext(..))
import Hatter.Widget
  ( Widget(..)
  , TextConfig(..)
  , ButtonConfig(..)
  , WidgetStyle(..)
  , defaultStyle
  , column
  )

main :: IO (Ptr AppContext)
main = do
  actionState <- newActionState
  -- False = position A (0,0), True = position B (120,80)
  atPositionB <- newIORef False

  moveAction <- runActionM actionState $ createAction $ do
    writeIORef atPositionB True
    platformLog "Moved to position B (translateX=120, translateY=80)"

  resetAction <- runActionM actionState $ createAction $ do
    writeIORef atPositionB False
    platformLog "Reset to position A (translateX=0, translateY=0)"

  let viewFn :: UserState -> IO Widget
      viewFn _userState = do
        isAtB <- readIORef atPositionB
        let translateX = if isAtB then 120.0 else 0.0
            translateY = if isAtB then 80.0 else 0.0
        pure $ column
          [ Animated (AnimatedConfig 400 EaseIn) $
              Styled (defaultStyle { wsTranslateX = Just translateX
                                   , wsTranslateY = Just translateY
                                   }) $
                Text TextConfig
                  { tcLabel = "EaseIn " <> pack (show translateX) <> "," <> pack (show translateY)
                  , tcFontConfig = Nothing
                  }
          , Button ButtonConfig
              { bcLabel = "Move Text"
              , bcAction = moveAction
              , bcFontConfig = Nothing
              }
          , Button ButtonConfig
              { bcLabel = "Reset"
              , bcAction = resetAction
              , bcFontConfig = Nothing
              }
          ]
      app = MobileApp
        { maContext     = loggingMobileContext
        , maView        = viewFn
        , maActionState = actionState
        }
  ctxPtr <- startMobileApp app
  platformLog "EaseInTranslateDemoMain started"
  pure ctxPtr
