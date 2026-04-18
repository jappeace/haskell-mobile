{-# LANGUAGE OverloadedStrings #-}
-- | Confetti animation demo using easeOut smart constructor.
--
-- Each particle gets its own Animated wrapper with easeOut:
-- origin (0,0) -> target (offsetX, offsetY) over 1.2 seconds.
module Main where

import Data.IORef (newIORef, readIORef, writeIORef)
import Foreign.Ptr (Ptr)
import Hatter
  ( MobileApp(..)
  , UserState(..)
  , easeOutAnimation
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

-- | A confetti particle with an easeOut animation from origin to target.
confettiParticle :: Double -> Double -> Widget
confettiParticle offsetX offsetY =
  let config = easeOutAnimation 1.2
                 (defaultStyle { wsTranslateX = Just 0, wsTranslateY = Just 0 })
                 (defaultStyle { wsTranslateX = Just offsetX, wsTranslateY = Just offsetY })
  in Animated config $
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
