{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the demo app.
--
-- The platform bridge (Android JNI, iOS Swift) runs this @main@
-- after @hs_init@ via the RTS API (@rts_evalLazyIO@ on the
-- @ZCMain_main_closure@ symbol). No @foreign export ccall@ needed.
--
-- Downstream users write their own version of this file with a
-- plain @main :: IO ()@ that calls @runMobileApp@.
module Main where

import HaskellMobile (runMobileApp, platformLog)
import HaskellMobile.App (mobileApp)

-- | Register the app so all FFI exports can find it.
main :: IO ()
main = do
  runMobileApp mobileApp
  platformLog "Haskell app registered"
