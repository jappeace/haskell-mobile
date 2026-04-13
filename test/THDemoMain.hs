{-# LANGUAGE OverloadedStrings #-}
-- | Entry point for the TH cross-compilation test.
--
-- Imports from th-consumer, a dependency package that uses a TH splice.
-- The splice runs during cross-compilation of th-consumer (via the Nix
-- haskellPackages infrastructure), not in this main module.
-- If this builds for aarch64-android, TH cross-compilation works.
module Main where

import Data.Text (pack)
import Foreign.Ptr (Ptr)
import THConsumer (thGreeting)
import Hatter (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), AppContext, newActionState)
import Hatter.Widget (TextConfig(..), Widget(..))

main :: IO (Ptr AppContext)
main = do
  platformLog ("TH test app: " <> pack thGreeting)
  actionState <- newActionState
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> pure (Text TextConfig { tcLabel = "th-demo", tcFontConfig = Nothing })
    , maActionState = actionState
    }
