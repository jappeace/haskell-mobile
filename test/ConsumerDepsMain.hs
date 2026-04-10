{-# LANGUAGE OverloadedStrings #-}
-- | Minimal consumer app that uses sqlite-simple.
--
-- sqlite-simple transitively depends on vector, which pulls in tasty
-- and optparse-applicative via cabal2nix sub-library merging.
-- This test verifies those test frameworks are filtered out and don't
-- cause link failures (tasty depends on unix/process, which are boot
-- packages not linked into the .so).
module Main where

import Foreign.Ptr (Ptr)
import HaskellMobile (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), AppContext, newActionState)
import HaskellMobile.Widget (TextConfig(..), Widget(..))

main :: IO (Ptr AppContext)
main = do
  platformLog "Consumer deps test app registered"
  actionState <- newActionState
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> pure (Text TextConfig { tcLabel = "consumer-deps", tcFontConfig = Nothing })
    , maActionState = actionState
    }
