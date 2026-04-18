{-# LANGUAGE OverloadedStrings #-}
-- | Self-contained animation demo app.
--
-- A button toggles padding between 10 and 50, using a linear
-- animation over 0.5 seconds.  The desktop stub fires test frames
-- synchronously, which exercises the tween interpolation path and
-- logs progress to stderr.
module Main where

import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (pack)
import Foreign.Ptr (Ptr)
import Hatter
  ( MobileApp(..)
  , UserState(..)
  , linearAnimation
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
  paddingRef <- newIORef (10.0 :: Double)
  toggleAction <- runActionM actionState $ createAction $ do
    currentPadding <- readIORef paddingRef
    let newPadding = if currentPadding < 30.0 then 50.0 else 10.0
    writeIORef paddingRef newPadding
    platformLog ("Toggled padding to " <> pack (show newPadding))
  let viewFn :: UserState -> IO Widget
      viewFn _userState = do
        currentPadding <- readIORef paddingRef
        let config = linearAnimation 0.5
                       (defaultStyle { wsPadding = Just 0 })
                       (defaultStyle { wsPadding = Just currentPadding })
        pure $ column
          [ Animated config $
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
