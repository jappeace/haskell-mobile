{-# LANGUAGE OverloadedStrings #-}
-- | Confetti animation demo using keyframe API.
--
-- Each particle gets its own 2-keyframe Animated wrapper:
-- origin (0,0) -> target (offsetX, offsetY) over 1.2 seconds.
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

-- | A confetti particle with a 2-keyframe animation from origin to target.
confettiParticle :: Double -> Double -> Widget
confettiParticle offsetX offsetY =
  let keyframes =
        [ Keyframe (unsafeKeyframeAt 0)
            (defaultStyle { wsTranslateX = Just 0, wsTranslateY = Just 0 })
        , Keyframe (unsafeKeyframeAt 1)
            (defaultStyle { wsTranslateX = Just offsetX, wsTranslateY = Just offsetY })
        ]
  in Animated (AnimatedConfig 1.2 keyframes) $
       Styled (defaultStyle { wsTranslateX = Just offsetX
                            , wsTranslateY = Just offsetY
                            }) $
         Text TextConfig
           { tcLabel = "*"
           , tcFontConfig = Nothing
           }

-- | Five confetti particles with fixed offsets.
confettiParticles :: [Widget]
confettiParticles =
  [ confettiParticle 120.0 50.0
  , confettiParticle (-80.0) 30.0
  , confettiParticle 50.0 100.0
  , confettiParticle (-110.0) 40.0
  , confettiParticle 30.0 70.0
  ]

main :: IO (Ptr AppContext)
main = do
  actionState <- newActionState
  showConfetti <- newIORef False

  triggerAction <- runActionM actionState $ createAction $ do
    writeIORef showConfetti True
    platformLog "Confetti triggered"

  let viewFn :: UserState -> IO Widget
      viewFn _userState = do
        isShowing <- readIORef showConfetti
        pure $ if isShowing
          then column
            ( confettiParticles ++
            [ Button ButtonConfig
                { bcLabel = "Confetti Active"
                , bcAction = triggerAction
                , bcFontConfig = Nothing
                }
            ])
          else column
            [ Button ButtonConfig
                { bcLabel = "Trigger Confetti"
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
  platformLog "ConfettiRepDemoMain started"
  pure ctxPtr
