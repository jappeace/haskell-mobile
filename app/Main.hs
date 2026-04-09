{-# LANGUAGE OverloadedStrings #-}
module Main where

import HaskellMobile (startMobileApp, platformLog, AppContext(..), derefAppContext)
import HaskellMobile.App (mobileApp)
import HaskellMobile.Lifecycle (LifecycleEvent(..), MobileContext(onLifecycle))

-- | Desktop entry point. Creates the app context, then simulates a mobile
-- lifecycle to exercise the callbacks.
--
-- On Android\/iOS, the platform bridge runs the user's @main@ via
-- @haskellRunMain()@ (cbits\/run_main.c) instead of GHC's generated
-- C main stub.
main :: IO ()
main = do
  ctxPtr <- startMobileApp mobileApp
  appCtx <- derefAppContext ctxPtr
  platformLog "Haskell app registered"
  let listen = onLifecycle (acMobileContext appCtx)

  -- Simulate the platform sending lifecycle events
  listen Create
  listen Start
  listen Resume

  platformLog "App is now in foreground"

  listen Pause
  listen Stop
  listen LowMemory
  listen Destroy

  platformLog "App lifecycle complete"
