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
import HaskellMobile (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), AppContext)
import HaskellMobile.Widget (TextConfig(..), Widget(..))

main :: IO (Ptr AppContext)
main = do
  platformLog ("TH test app: " <> pack thGreeting)
  startMobileApp thDemoApp

-- | Minimal app for Template Haskell cross-compilation verification.
thDemoApp :: MobileApp
thDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = \_userState -> pure (Text TextConfig { tcLabel = "th-demo", tcFontConfig = Nothing })
  }
