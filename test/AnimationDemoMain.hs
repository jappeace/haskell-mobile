{-# LANGUAGE OverloadedStrings #-}
-- | Self-contained animation demo app.
--
-- A button toggles padding between 10 and 50, wrapped in
-- @Animated 500 EaseInOut@.  The desktop stub fires test frames
-- synchronously (0ms, 16.67ms, 1000ms), which exercises the
-- tween interpolation path and logs progress to stderr.
module Main where

import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (pack)
import Foreign.Ptr (Ptr)
import HaskellMobile
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
import HaskellMobile.AppContext (AppContext(..))
import HaskellMobile.Widget
  ( Widget(..)
  , TextConfig(..)
  , ButtonConfig(..)
  , WidgetStyle(..)
  , defaultStyle
  )

main :: IO (Ptr AppContext)
main = do
  actionState <- newActionState
  paddingRef <- newIORef (10.0 :: Double)
  toggleAction <- runActionM actionState $ createAction $ do
    currentPadding <- readIORef paddingRef
    let newPadding = if currentPadding < 30.0 then 50.0 else 10.0
    writeIORef paddingRef newPadding
    platformLog ("Toggled padding to " <> pack (show newPadding))
  let viewFn :: UserState -> IO Widget
      viewFn _userState = do
        currentPadding <- readIORef paddingRef
        pure $ Column
          [ Animated (AnimatedConfig 500 EaseInOut) $
              Styled (defaultStyle { wsPadding = Just currentPadding }) $
                Text TextConfig
                  { tcLabel = "Animated padding"
                  , tcFontConfig = Nothing
                  }
          , Button ButtonConfig
              { bcLabel = "Toggle Padding"
              , bcAction = toggleAction
              , bcFontConfig = Nothing
              }
          ]
      app = MobileApp
        { maContext     = loggingMobileContext
        , maView        = viewFn
        , maActionState = actionState
        }
  ctxPtr <- startMobileApp app
  platformLog "AnimationDemoMain started"
  pure ctxPtr
