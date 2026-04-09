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
import HaskellMobile (startMobileApp, platformLog, AppContext)
import HaskellMobile.App (mobileApp)

main :: IO (Ptr AppContext)
main = do
  platformLog ("TH test app: " <> pack thGreeting)
  startMobileApp mobileApp
