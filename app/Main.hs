module Main where

import HaskellMobile (loggingMobileContext, platformLog)
import HaskellMobile.Lifecycle (LifecycleEvent(..), MobileContext(onLifecycle))

-- | Simulate a mobile app lifecycle.
-- On Android\/iOS the platform bridge dispatches these events via
-- 'haskellOnLifecycle'.  Here we drive them from Haskell to show
-- that the listener callback fires for every event.
main :: IO ()
main = do
  platformLog "Waiting for lifecycle events..."
  let listen = onLifecycle loggingMobileContext

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
