{-# LANGUAGE OverloadedStrings #-}
-- | Reproducer for confetti animation bug.
--
-- The prrrrrrrrr confetti pattern creates particles at their final
-- scattered positions on first render.  Because the Animated wrapper
-- only triggers tweens on property *changes* between renders (in
-- diffRenderNode), the first render goes through createRenderedNode
-- which places nodes at their target positions immediately — no
-- "from" state exists to animate from.
--
-- Expected: particles fly outward from centre over 1200ms.
-- Actual:   particles appear instantly at final positions.
--
-- To verify the bug, check logcat for the absence of
-- setNumProp.*translateX calls — no tween is ever registered.
module Main where

import Data.IORef (newIORef, readIORef, writeIORef)
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

-- | A confetti particle: a styled "*" with translateX/Y offsets.
confettiParticle :: Double -> Double -> Widget
confettiParticle offsetX offsetY =
  Styled (defaultStyle { wsTranslateX = Just offsetX
                       , wsTranslateY = Just offsetY
                       }) $
    Text TextConfig
      { tcLabel = "*"
      , tcFontConfig = Nothing
      }

-- | Five confetti particles with fixed "random-ish" offsets.
-- Mimics the prrrrrrrrr pattern: particles are created at their
-- final scattered positions wrapped in a single Animated node.
confettiParticles :: [Widget]
confettiParticles =
  [ confettiParticle 120.0 (-90.0)
  , confettiParticle (-80.0) (-60.0)
  , confettiParticle 50.0 100.0
  , confettiParticle (-110.0) 40.0
  , confettiParticle 30.0 (-120.0)
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
            [ Animated (AnimatedConfig 1200 EaseOut) $
                column confettiParticles
            , Button ButtonConfig
                { bcLabel = "Confetti Active"
                , bcAction = triggerAction
                , bcFontConfig = Nothing
                }
            ]
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
