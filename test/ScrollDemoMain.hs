{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the scroll-demo test app.
--
-- Used by the emulator and simulator ScrollView integration tests.
-- Starts directly in scroll-demo mode so no runtime switching is needed.
module Main where

import Foreign.Ptr (Ptr)
import HaskellMobile (startMobileApp, platformLog, AppContext)
import HaskellMobile.App (scrollDemoApp)

main :: IO (Ptr AppContext)
main = do
  platformLog "Scroll demo app registered"
  startMobileApp scrollDemoApp
