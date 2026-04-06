{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the text-input-demo test app.
--
-- Used by the emulator and simulator TextInput integration tests.
-- Starts directly in text-input-demo mode so no runtime switching is needed.
module Main where

import HaskellMobile (runMobileApp, platformLog)
import HaskellMobile.App (textInputDemoApp)

main :: IO ()
main = do
  runMobileApp textInputDemoApp
  platformLog "TextInput demo app registered"
