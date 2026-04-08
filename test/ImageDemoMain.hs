{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the image-demo test app.
--
-- Used by the emulator and simulator Image integration tests.
-- Starts directly in image-demo mode so no runtime switching is needed.
module Main where

import HaskellMobile (runMobileApp, platformLog)
import HaskellMobile.App (imageDemoApp)

main :: IO ()
main = do
  runMobileApp imageDemoApp
  platformLog "Image demo app registered"
