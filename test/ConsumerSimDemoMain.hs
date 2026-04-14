{-# LANGUAGE OverloadedStrings #-}
-- | Consumer simulation demo app — exercises the crossDeps + extraJniBridge
-- build path with a non-boot Hackage dependency (hashable).
--
-- This reproduces the build configuration used by real consumer apps like
-- prrrrrrrrr, which crashed with SIGSEGV at startup (issue #156).
-- Hatter's own test APKs all use empty crossDeps; this test ensures the
-- consumer build path also produces a working .so under ARM binary translation.
module Main where

import Data.Hashable (hash)
import Data.Text qualified as Text
import Foreign.Ptr (Ptr)
import Hatter (MobileApp(..), startMobileApp, platformLog, loggingMobileContext, newActionState)
import Hatter.AppContext (AppContext)
import Hatter.Widget (Widget(..), TextConfig(..))

main :: IO (Ptr AppContext)
main = do
  platformLog "ConsumerSim demo app registered"
  platformLog ("hashable sanity: " <> Text.pack (show (hash ("test" :: String))))
  actionState <- newActionState
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> pure (Text TextConfig { tcLabel = "Consumer sim", tcFontConfig = Nothing })
    , maActionState = actionState
    }
