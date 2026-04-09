{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the demo app.
--
-- The platform bridge (Android JNI, iOS Swift) runs this @main@
-- after @hs_init@ via the RTS API (@rts_evalIO@ on the
-- @ZCMain_main_closure@ symbol). No @foreign export ccall@ needed.
--
-- Downstream users write their own version of this file with a
-- plain @main :: IO (Ptr AppContext)@ that calls @startMobileApp@.
module Main where

import Foreign.Ptr (Ptr)
import HaskellMobile (startMobileApp, platformLog, AppContext)
import HaskellMobile.App (mobileApp)

-- | Create the app context and return it to the platform bridge.
main :: IO (Ptr AppContext)
main = do
  platformLog "Haskell app registered"
  startMobileApp mobileApp
