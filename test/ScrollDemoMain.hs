{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the scroll-demo test app.
--
-- Used by the emulator and simulator ScrollView integration tests.
-- Starts directly in scroll-demo mode so no runtime switching is needed.
module Main where

import HaskellMobile (runMobileApp, platformLog)
import HaskellMobile.App (scrollDemoApp)

main :: IO ()
main = do
  runMobileApp scrollDemoApp
  platformLog "Scroll demo app registered"
