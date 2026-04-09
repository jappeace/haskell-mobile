{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the text-input-demo test app.
--
-- Used by the emulator and simulator TextInput integration tests.
-- Starts directly in text-input-demo mode so no runtime switching is needed.
module Main where

import Foreign.Ptr (Ptr)
import HaskellMobile (startMobileApp, platformLog, AppContext)
import HaskellMobile.App (textInputDemoApp)

main :: IO (Ptr AppContext)
main = do
  platformLog "TextInput demo app registered"
  startMobileApp textInputDemoApp
