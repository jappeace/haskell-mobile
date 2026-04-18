{-# LANGUAGE OverloadedStrings #-}
-- | Keyframe animation demo app.
--
-- A trigger button starts a 3-keyframe animation on a "*" text:
--   kfAt 0.0: translateX=0, translateY=0
--   kfAt 0.5: translateX=200, translateY=100
--   kfAt 1.0: translateX=200, translateY=0
--
-- Duration: 2.0 seconds.
module Main where

import Data.IORef (newIORef, readIORef, writeIORef)
import Foreign.Ptr (Ptr)
import Hatter
  ( MobileApp(..)
  , UserState(..)
  , AnimatedConfig(..)
  , Keyframe(..)
  , KeyframeAt
  , mkKeyframeAt
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

-- | Unsafely create a KeyframeAt, assuming the value is in [0,1].
unsafeKeyframeAt :: Rational -> Hatter.KeyframeAt
unsafeKeyframeAt value = case mkKeyframeAt (fromRational value) of
  Just kfAt -> kfAt
  Nothing   -> error ("Invalid keyframe position: " ++ show value)

main :: IO (Ptr AppContext)
main = do
  actionState <- newActionState
  triggered <- newIORef False

  triggerAction <- runActionM actionState $ createAction $ do
    writeIORef triggered True
    platformLog "Keyframe triggered"

  let keyframes =
        [ Keyframe (unsafeKeyframeAt 0)
            (defaultStyle { wsTranslateX = Just 0, wsTranslateY = Just 0 })
        , Keyframe (unsafeKeyframeAt 0.5)
            (defaultStyle { wsTranslateX = Just 200, wsTranslateY = Just 100 })
        , Keyframe (unsafeKeyframeAt 1)
            (defaultStyle { wsTranslateX = Just 200, wsTranslateY = Just 0 })
        ]

  let viewFn :: UserState -> IO Widget
      viewFn _userState = do
        isTriggered <- readIORef triggered
        pure $ if isTriggered
          then column
            [ Animated (AnimatedConfig 2.0 keyframes) $
                Styled (defaultStyle { wsTranslateX = Just 200, wsTranslateY = Just 0 }) $
                  Text TextConfig
                    { tcLabel = "*"
                    , tcFontConfig = Nothing
                    }
            , Button ButtonConfig
                { bcLabel = "Trigger Keyframe"
                , bcAction = triggerAction
                , bcFontConfig = Nothing
                }
            ]
          else column
            [ Text TextConfig
                { tcLabel = "*"
                , tcFontConfig = Nothing
                }
            , Button ButtonConfig
                { bcLabel = "Trigger Keyframe"
                , bcAction = triggerAction
                , bcFontConfig = Nothing
                }
            ]
      app = MobileApp
        { maContext     = loggingMobileContext
        , maView        = viewFn
        , maActionState = actionState
        }
  ctxPtr <- startMobileApp app
  platformLog "KeyframeDemo started"
  pure ctxPtr
